defmodule Kakemono.Widgets.Slideshow do
  @moduledoc """
  Slideshow widget: renders the items of a Playlist as a fading
  image/video carousel inside whatever container it is mounted in.

  Lives in a 12x12 grid cell when used in a `dashboard` scene, or fills
  the screen when used as the sole widget of a `fullscreen_widget` scene.
  In both cases it positions its layers absolutely *inside its mount*,
  so the surrounding cell controls its real size.

  Config:
    * `playlist_id` (required, integer)
    * `interval_ms` (optional, integer >= 2000) — overrides per-item duration
    * `fit_mode`    (optional, "contain" | "cover") — overrides playlist default
  """

  use Kakemono.Widget

  alias Kakemono.{Playlists, Media}

  @impl true
  def type, do: "slideshow"

  @impl true
  def name, do: "Slideshow"

  @impl true
  def icon, do: "🖼"

  @impl true
  def fields do
    [
      %{key: "playlist_id", label: "Playlist", type: :playlist_select, required: true},
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
  Resolve the playlist + items for an instance. Items are LiveView-shaped
  maps the Slideshow JS hook understands.
  """
  def items_for(%Kakemono.Widgets.Instance{config: cfg}) do
    case cfg["playlist_id"] do
      nil ->
        {nil, []}

      pid when is_integer(pid) ->
        case Playlists.get_with_items(pid) do
          nil -> {nil, []}
          pl -> {pl, entries_to_items(pl, cfg)}
        end

      _ ->
        {nil, []}
    end
  end

  @doc "Resolved fit mode, honouring widget config first, playlist default second."
  def fit_mode(%Kakemono.Widgets.Instance{config: cfg}, playlist) do
    cfg["fit_mode"] || (playlist && playlist.fit_mode) || "contain"
  end

  defp entries_to_items(%{entries: entries, transition_duration_ms: pl_override}, cfg) do
    cfg_override = cfg["interval_ms"]

    Enum.map(entries, fn e ->
      m = e.media_item

      %{
        id: m.id,
        src: Media.url(m),
        type: Atom.to_string(Kakemono.Media.Item.kind(m)),
        duration_ms: cfg_override || pl_override || m.duration_ms || 6000
      }
    end)
  end

  @impl true
  def render(assigns) do
    {pl, items} = items_for(assigns.instance)
    fit = fit_mode(assigns.instance, pl)

    assigns = Map.merge(assigns, %{items: items, fit_mode: fit, playlist: pl})

    ~H"""
    <div
      id={"slideshow-" <> Integer.to_string(@instance.id)}
      phx-hook="Slideshow"
      data-instance-id={@instance.id}
      data-items={Jason.encode!(@items)}
      data-fit-mode={@fit_mode}
      class="kakemono-widget kakemono-widget-slideshow relative w-full h-full bg-black overflow-hidden"
    >
      <div
        :if={@items == []}
        class="absolute inset-0 flex items-center justify-center text-white/60 text-sm p-4 text-center"
      >
        <%= cond do %>
          <% is_nil(@playlist) -> %>
            No playlist configured.
          <% true -> %>
            Playlist "{@playlist.name}" is empty.
        <% end %>
      </div>
    </div>
    """
  end
end
