defmodule Kakemono.Widgets.Instagram do
  @moduledoc """
  Instagram widget: cycles through the latest public posts of an
  Instagram user as a fading image carousel. Mounts the same JS hook
  as the Slideshow widget so the rendering logic is shared.

  Fetching is best-effort against Instagram's public web endpoint and
  may break without warning (the user picked this trade-off knowingly).

  Config:
    * `username`    (required, string) — IG handle without `@`
    * `max_items`   (optional, 1..20) — number of posts to keep
    * `interval_ms` (optional, >= 2000) — duration per slide
    * `fit_mode`    (optional, "contain" | "cover")
  """

  @behaviour Kakemono.Widget
  use Phoenix.Component

  @impl true
  def type, do: "instagram"

  @impl true
  def name, do: "Instagram"

  @impl true
  def config_schema do
    %{
      "type" => "object",
      "required" => ["username"],
      "properties" => %{
        "username" => %{"type" => "string", "minLength" => 1},
        "max_items" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
        "interval_ms" => %{"type" => "integer", "minimum" => 2000},
        "fit_mode" => %{"type" => "string", "enum" => ["contain", "cover"]},
        "cached_items" => %{"type" => "array"},
        "last_error" => %{"type" => "string"}
      },
      "additionalProperties" => false
    }
  end

  @impl true
  def default_config, do: %{"max_items" => 9}

  @impl true
  def prefetch(%Kakemono.Widgets.Instance{id: id, config: cfg}) do
    username = cfg["username"]
    items = cfg["cached_items"]

    if is_binary(username) and username != "" and (is_nil(items) or items == []) do
      %{instance_id: id}
      |> Kakemono.Widgets.InstagramFetchWorker.new()
      |> Oban.insert!()
    end

    :ok
  end

  @impl true
  def config_fields do
    [
      %{
        key: "username",
        label: "Instagram handle",
        type: :text,
        required: true,
        placeholder: "nasa"
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
