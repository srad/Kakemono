defmodule Kakemono.Widgets.InstagramFetchWorker do
  @moduledoc """
  Fetches recent public posts for a single Instagram widget instance and
  caches them in `instance.config["cached_items"]`.

  Uses Instagram's media API when an `access_token` is configured, otherwise
  falls back to the public `web_profile_info` endpoint. The public endpoint is
  unauthenticated scraping and Instagram aggressively rate-limits or blocks it
  — failures are stored on the instance as `last_error` and surface in the
  rendered widget.

  Enqueued by `Kakemono.Widgets.InstagramScheduler` (Oban.Cron) once an
  hour. HTTP client is `Req`. Tests stub via `Req.Test`.
  """
  use Oban.Worker,
    queue: :widgets,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]]

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Instagram, Instance}

  @web_profile_endpoints [
    "https://www.instagram.com/api/v1/users/web_profile_info/",
    "https://i.instagram.com/api/v1/users/web_profile_info/"
  ]
  @graph_endpoint "https://graph.instagram.com/me/media"
  @ig_app_id "936619743392459"
  @rate_limit_backoff_seconds 6 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id}}) do
    case Widgets.get_instance(id) do
      %Instance{widget_type: "instagram", config: cfg} = inst ->
        case fetch(cfg) do
          {:ok, :graph, body} ->
            cache_items(inst, cfg, Instagram.parse_graph_media(body))

          {:ok, :web_profile, body} ->
            cache_items(inst, cfg, Instagram.parse_profile(body))

          {:error, reason} ->
            store_error(inst, cfg, reason)
        end

      %Instance{widget_type: type} ->
        {:error, {:wrong_type, type}}

      nil ->
        :ok
    end
  end

  defp cache_items(inst, cfg, items) do
    max = cfg["max_items"] || 9
    trimmed = Enum.take(items, max)

    update =
      cfg
      |> Map.put("cached_items", trimmed)
      |> Map.put("last_fetch_at", timestamp())
      |> Map.delete("last_error")
      |> Map.delete("last_error_at")
      |> Map.delete("next_fetch_at")

    with {:ok, _} <- Widgets.update_config(inst, update) do
      broadcast(inst.id)
      :ok
    end
  end

  defp store_error(inst, cfg, reason) do
    update =
      cfg
      |> Map.put("last_error", error_message(reason))
      |> Map.put("last_error_at", timestamp())
      |> maybe_put_backoff(reason)

    with {:ok, _} <- Widgets.update_config(inst, update) do
      broadcast(inst.id)

      if retryable_error?(reason) do
        {:error, reason}
      else
        :ok
      end
    end
  end

  defp fetch(%{"access_token" => token} = cfg) when is_binary(token) do
    case String.trim(token) do
      "" -> fetch_web_profile(cfg["username"])
      token -> fetch_graph_media(token, cfg["max_items"] || 9)
    end
  end

  defp fetch(%{"username" => username}), do: fetch_web_profile(username)
  defp fetch(_), do: {:error, :no_username}

  defp fetch_web_profile(nil), do: {:error, :no_username}
  defp fetch_web_profile(""), do: {:error, :no_username}

  defp fetch_web_profile(username) when is_binary(username) do
    username = username |> String.trim() |> String.trim_leading("@")

    opts =
      Application.get_env(:kakemono, :req_options, [])
      |> Keyword.merge(
        params: [username: username],
        retry: false,
        headers: [
          {"x-ig-app-id", @ig_app_id},
          {"user-agent",
           "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"},
          {"accept", "application/json"},
          {"accept-language", "en-US,en;q=0.9"},
          {"referer", "https://www.instagram.com/" <> username <> "/"},
          {"x-requested-with", "XMLHttpRequest"}
        ]
      )

    Enum.reduce_while(@web_profile_endpoints, {:error, :no_username}, fn endpoint, _last_error ->
      case request(endpoint, opts, :web_profile) do
        {:error, {:http_status, 429}} = error -> {:cont, error}
        {:error, {:instagram_error, 429, _message}} = error -> {:cont, error}
        result -> {:halt, result}
      end
    end)
  end

  defp fetch_graph_media(access_token, max_items) do
    opts =
      Application.get_env(:kakemono, :req_options, [])
      |> Keyword.merge(
        params: [
          access_token: access_token,
          limit: max_items,
          fields:
            "id,caption,media_type,media_url,permalink,thumbnail_url,timestamp,username,children{media_type,media_url,thumbnail_url,permalink}"
        ],
        retry: false,
        headers: [{"accept", "application/json"}]
      )

    request(@graph_endpoint, opts, :graph)
  end

  defp request(endpoint, opts, source) do
    case Req.get(endpoint, opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, source, normalize_body(body)}

      {:ok, %Req.Response{status: status, body: %{"error" => %{"message" => message}}}}
      when is_binary(message) ->
        {:error, {:instagram_error, status, message}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp error_message(:no_username), do: "no username configured"
  defp error_message({:http_status, s}), do: "HTTP #{s}"
  defp error_message({:instagram_error, s, message}), do: "HTTP #{s}: #{message}"
  defp error_message(reason), do: inspect(reason)

  defp normalize_body(body) when is_binary(body), do: body
  defp normalize_body(body) when is_map(body), do: Jason.encode!(body)
  defp normalize_body(body) when is_list(body), do: Jason.encode!(body)
  defp normalize_body(body), do: to_string(body)

  defp maybe_put_backoff(cfg, {:http_status, 429}), do: put_backoff(cfg)
  defp maybe_put_backoff(cfg, {:instagram_error, 429, _message}), do: put_backoff(cfg)
  defp maybe_put_backoff(cfg, _reason), do: cfg

  defp put_backoff(cfg) do
    Map.put(cfg, "next_fetch_at", timestamp(@rate_limit_backoff_seconds))
  end

  defp retryable_error?({:http_status, status}) when status in 500..599, do: true
  defp retryable_error?({:instagram_error, status, _message}) when status in 500..599, do: true
  defp retryable_error?(_), do: false

  defp timestamp(offset_seconds \\ 0) do
    DateTime.utc_now()
    |> DateTime.add(offset_seconds, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp broadcast(instance_id) do
    Phoenix.PubSub.broadcast(
      Kakemono.PubSub,
      "widgets",
      {:widget_config_updated, %{instance_id: instance_id}}
    )
  end
end
