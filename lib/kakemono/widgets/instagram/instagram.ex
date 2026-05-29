defmodule Kakemono.Widgets.Instagram do
  @moduledoc """
  Instagram widget: cycles through the latest public posts of an
  Instagram user as a fading image carousel. Mounts the same JS hook
  as the Slideshow widget so the rendering logic is shared.

  Fetching is best-effort against Instagram's public web endpoint and
  may break without warning (the user picked this trade-off knowingly).

  Config:
    * `username`    (required, string) — IG handle without `@`
    * `access_token` (optional, string) — token for Instagram's API
    * `max_items`   (optional, 1..20) — number of posts to keep
    * `interval_ms` (optional, >= 2000) — duration per slide
    * `fit_mode`    (optional, "contain" | "cover")
  """

  use Kakemono.Widget

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{FetchWorker, Instance}

  @web_profile_endpoints [
    "https://www.instagram.com/api/v1/users/web_profile_info/",
    "https://i.instagram.com/api/v1/users/web_profile_info/"
  ]
  @graph_endpoint "https://graph.instagram.com/me/media"
  @ig_app_id "936619743392459"
  @rate_limit_backoff_seconds 6 * 60 * 60

  @impl true
  def type, do: "instagram"

  @impl true
  def name, do: "Instagram"

  @impl true
  def icon, do: "📸"

  @impl true
  def cache_fields do
    [
      {"cached_items", "array"},
      {"last_error", "string"},
      {"last_error_at", "string"},
      {"last_fetch_at", "string"},
      {"next_fetch_at", "string"}
    ]
  end

  @impl true
  def prefetch(%Instance{id: id, config: cfg}) do
    if configured_username?(cfg["username"]) and empty_items?(cfg["cached_items"]) and
         fetch_due?(cfg),
       do: enqueue_fetch(id)

    :ok
  end

  @impl true
  def on_config_change(%Instance{id: id, config: cfg}, old_config) do
    if source_changed?(cfg, old_config) and configured_username?(cfg["username"]),
      do: enqueue_fetch(id)

    :ok
  end

  @impl true
  def merge_config(old, new) do
    merged = Map.merge(old, new)

    if source_changed?(merged, old) do
      Map.drop(merged, [
        "cached_items",
        "last_error",
        "last_error_at",
        "last_fetch_at",
        "next_fetch_at"
      ])
    else
      merged
    end
  end

  @impl true
  def fetch(%Instance{config: cfg} = inst) do
    if fetch_due?(cfg) do
      case do_remote_fetch(cfg) do
        {:ok, :graph, body} -> store_items(inst, cfg, parse_graph_media(body))
        {:ok, :web_profile, body} -> store_items(inst, cfg, parse_profile(body))
        {:error, reason} -> store_error(inst, cfg, reason)
      end
    else
      :skip
    end
  end

  defp source_changed?(cfg, old_config) do
    cfg["username"] != old_config["username"] or
      cfg["access_token"] != old_config["access_token"]
  end

  defp enqueue_fetch(id) do
    %{instance_id: id} |> FetchWorker.new() |> Oban.insert!()
  end

  defp store_items(inst, cfg, items) do
    max = cfg["max_items"] || 9
    trimmed = Enum.take(items, max)

    update =
      cfg
      |> Map.put("cached_items", trimmed)
      |> Map.put("last_fetch_at", timestamp())
      |> Map.delete("last_error")
      |> Map.delete("last_error_at")
      |> Map.delete("next_fetch_at")

    with {:ok, _} <- Widgets.update_config(inst, update), do: :ok
  end

  defp store_error(inst, cfg, reason) do
    update =
      cfg
      |> Map.put("last_error", error_message(reason))
      |> Map.put("last_error_at", timestamp())
      |> maybe_put_backoff(reason)

    with {:ok, _} <- Widgets.update_config(inst, update) do
      if retryable_error?(reason), do: {:error, reason}, else: :ok
    end
  end

  defp do_remote_fetch(%{"access_token" => token} = cfg) when is_binary(token) do
    case String.trim(token) do
      "" -> fetch_web_profile(cfg["username"])
      token -> fetch_graph_media(token, cfg["max_items"] || 9)
    end
  end

  defp do_remote_fetch(%{"username" => username}), do: fetch_web_profile(username)
  defp do_remote_fetch(_), do: {:error, :no_username}

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

  @impl true
  def fields do
    [
      %{
        key: "username",
        label: "Instagram handle",
        type: :text,
        required: true,
        min_length: 1,
        placeholder: "nasa"
      },
      %{
        key: "access_token",
        label: "Access token",
        type: :password,
        required: false,
        min_length: 1,
        placeholder: "Instagram API token"
      },
      %{
        key: "max_items",
        label: "Max posts",
        type: :number,
        required: false,
        integer: true,
        min: 1,
        max: 20,
        step: "1",
        default: 9,
        placeholder: "9"
      },
      %{
        key: "interval_ms",
        label: "Interval (ms)",
        type: :number,
        required: false,
        integer: true,
        min: 2000,
        step: "1",
        placeholder: "6000"
      },
      %{
        key: "fit_mode",
        label: "Fit mode",
        type: :select,
        required: false,
        options: [{"", "— default —"}, {"contain", "contain"}, {"cover", "cover"}]
      }
    ]
  end

  @doc """
  Parse the JSON body returned by Instagram's `web_profile_info` endpoint
  into a list of item maps with string keys: `src`, `type`, `permalink`,
  `caption`. Videos return their thumbnail; we don't try to play IG video.
  """
  def parse_profile(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_profile(decoded)
      _ -> []
    end
  end

  def parse_profile(%{"data" => %{"user" => user}}) when is_map(user) do
    edges =
      get_in(user, ["edge_owner_to_timeline_media", "edges"]) ||
        get_in(user, ["edge_felix_video_timeline", "edges"]) || []

    edges
    |> Enum.map(fn
      %{"node" => node} -> node_to_item(node)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def parse_profile(_), do: []

  @doc """
  Parse the JSON returned by Instagram's API media endpoint into the same
  item maps used by the public-profile scraper.
  """
  def parse_graph_media(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_graph_media(decoded)
      _ -> []
    end
  end

  def parse_graph_media(%{"data" => data}) when is_list(data) do
    data
    |> Enum.map(&graph_media_to_item/1)
    |> Enum.reject(&is_nil/1)
  end

  def parse_graph_media(_), do: []

  defp node_to_item(node) when is_map(node) do
    src = node["display_url"] || node["thumbnail_src"]

    if is_binary(src) and src != "" do
      shortcode = node["shortcode"]

      %{
        "src" => src,
        "type" => "image",
        "permalink" =>
          if(is_binary(shortcode) and shortcode != "",
            do: "https://www.instagram.com/p/" <> shortcode <> "/",
            else: nil
          ),
        "caption" => extract_caption(node)
      }
    end
  end

  defp node_to_item(_), do: nil

  defp extract_caption(node) do
    case get_in(node, ["edge_media_to_caption", "edges"]) do
      [%{"node" => %{"text" => text}} | _] when is_binary(text) -> text
      _ -> ""
    end
  end

  defp graph_media_to_item(media) when is_map(media) do
    src = media["thumbnail_url"] || media["media_url"] || first_child_src(media)

    if is_binary(src) and src != "" do
      %{
        "src" => src,
        "type" => "image",
        "permalink" => media["permalink"],
        "caption" => media["caption"] || ""
      }
    end
  end

  defp graph_media_to_item(_), do: nil

  defp first_child_src(%{"children" => %{"data" => children}}) when is_list(children) do
    Enum.find_value(children, fn
      child when is_map(child) -> child["thumbnail_url"] || child["media_url"]
      _ -> nil
    end)
  end

  defp first_child_src(_), do: nil

  def fetch_due?(%Kakemono.Widgets.Instance{config: cfg}), do: fetch_due?(cfg)

  def fetch_due?(cfg) when is_map(cfg) do
    case parse_datetime(cfg["next_fetch_at"]) do
      {:ok, next_fetch_at} -> DateTime.compare(next_fetch_at, DateTime.utc_now()) != :gt
      :error -> true
    end
  end

  def fetch_due?(_), do: true

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp parse_datetime(_), do: :error

  defp configured_username?(username) when is_binary(username), do: String.trim(username) != ""
  defp configured_username?(_), do: false

  defp empty_items?(nil), do: true
  defp empty_items?([]), do: true
  defp empty_items?(_), do: false

  @impl true
  def render(assigns) do
    cfg = assigns.instance.config
    items = items_for(cfg)
    fit = cfg["fit_mode"] || "contain"
    interval = cfg["interval_ms"] || 6000

    slideshow_items =
      Enum.map(items, fn it ->
        %{
          id: it["src"],
          src: it["src"],
          type: "image",
          duration_ms: interval
        }
      end)

    assigns =
      Map.merge(assigns, %{
        items: slideshow_items,
        raw_items: items,
        fit_mode: fit,
        username: cfg["username"],
        last_error: cfg["last_error"]
      })

    ~H"""
    <div
      id={"instagram-" <> Integer.to_string(@instance.id)}
      phx-hook="Slideshow"
      data-instance-id={@instance.id}
      data-items={Jason.encode!(@items)}
      data-fit-mode={@fit_mode}
      class="kakemono-widget kakemono-widget-instagram relative w-full h-full bg-black overflow-hidden"
    >
      <div
        :if={@items == []}
        class="absolute inset-0 flex items-center justify-center text-white/60 text-sm p-4 text-center"
      >
        <%= cond do %>
          <% is_nil(@username) or @username == "" -> %>
            No Instagram handle configured.
          <% is_binary(@last_error) and @last_error != "" -> %>
            Could not load @{@username}: {@last_error}
          <% true -> %>
            Waiting for first fetch of @{@username}…
        <% end %>
      </div>
    </div>
    """
  end

  defp items_for(cfg) do
    max = cfg["max_items"] || 9
    (cfg["cached_items"] || []) |> Enum.take(max)
  end
end
