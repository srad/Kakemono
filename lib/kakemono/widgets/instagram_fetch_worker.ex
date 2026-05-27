defmodule Kakemono.Widgets.InstagramFetchWorker do
  @moduledoc """
  Fetches recent public posts for a single Instagram widget instance and
  caches them in `instance.config["cached_items"]`.

  Hits Instagram's `web_profile_info` endpoint with the public web app id.
  This is unauthenticated scraping and Instagram aggressively rate-limits
  or blocks it — failures are stored on the instance as `last_error` and
  surface in the rendered widget.

  Enqueued by `Kakemono.Widgets.InstagramScheduler` (Oban.Cron) once an
  hour. HTTP client is `Req`. Tests stub via `Req.Test`.
  """
  use Oban.Worker,
    queue: :widgets,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]]

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Instagram, Instance}

  @endpoint "https://i.instagram.com/api/v1/users/web_profile_info/"
  @ig_app_id "936619743392459"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id}}) do
    case Widgets.get_instance(id) do
      %Instance{widget_type: "instagram", config: cfg} = inst ->
        username = cfg["username"]

        case fetch(username) do
          {:ok, body} ->
            items = Instagram.parse_profile(body)
            max = cfg["max_items"] || 9
            trimmed = Enum.take(items, max)

            update =
              cfg
              |> Map.put("cached_items", trimmed)
              |> Map.delete("last_error")

            with {:ok, _} <- Widgets.update_config(inst, update) do
              broadcast(inst.id)
              :ok
            end

          {:error, reason} ->
            update = Map.put(cfg, "last_error", error_message(reason))
            _ = Widgets.update_config(inst, update)
            broadcast(inst.id)
            {:error, reason}
        end

      %Instance{widget_type: type} ->
        {:error, {:wrong_type, type}}

      nil ->
        :ok
    end
  end

  defp fetch(nil), do: {:error, :no_username}
  defp fetch(""), do: {:error, :no_username}

  defp fetch(username) when is_binary(username) do
    opts =
      Application.get_env(:kakemono, :req_options, [])
      |> Keyword.merge(
        params: [username: username],
        retry: false,
        headers: [
          {"x-ig-app-id", @ig_app_id},
          {"user-agent",
           "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"},
          {"accept", "application/json"}
        ]
      )

    case Req.get(@endpoint, opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, Jason.encode!(body)}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp error_message(:no_username), do: "no username configured"
  defp error_message({:http_status, s}), do: "HTTP #{s}"
  defp error_message(reason), do: inspect(reason)

  defp broadcast(instance_id) do
    Phoenix.PubSub.broadcast(
      Kakemono.PubSub,
      "widgets",
      {:widget_config_updated, %{instance_id: instance_id}}
    )
  end
end
