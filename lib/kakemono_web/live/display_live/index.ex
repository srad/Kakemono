defmodule KakemonoWeb.DisplayLive.Index do
  use KakemonoWeb, :live_view

  alias Kakemono.{Displays, Scenes, Widgets}
  alias Kakemono.Widgets.Slideshow

  @impl true
  def mount(%{"display_id" => id} = params, _session, socket) do
    display =
      case Displays.get(id) do
        nil ->
          {:ok, d} = Displays.upsert(%{id: id, name: humanize(id)})
          d

        d ->
          d
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:#{id}")
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "widgets")
      KakemonoWeb.Presence.track_display(self(), id)
    end

    override = params["scene"] && Scenes.get_by_name(params["scene"])
    active_id = if override, do: override.id, else: display.current_scene_id
    cells = load_scene_cells(active_id)

    if connected?(socket) do
      subscribe_scene(active_id)
      prefetch_cells(cells)
    end

    {:ok,
     socket
     |> assign(:display_id, id)
     |> assign(:display_name, display.name)
     |> assign(:override_scene, override)
     |> assign(:preview_weather, weather_preview(params))
     |> assign(:scene, load_scene(active_id))
     |> assign(:scene_cells, cells), layout: false}
  end

  defp prefetch_cells(cells) do
    Enum.each(cells, fn cell -> Widgets.prefetch_instance(cell.instance) end)
  end

  defp humanize(id) do
    id
    |> String.replace(["-", "_"], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp load_scene(nil), do: nil
  defp load_scene(id), do: Scenes.get(id)

  defp load_scene_cells(nil), do: []

  defp load_scene_cells(scene_id) do
    case Scenes.get(scene_id) do
      nil ->
        []

      %{mode: "dashboard", layout: %{"cells" => cells}} when is_list(cells) ->
        Enum.flat_map(cells, fn cell ->
          case Widgets.get_instance(cell["widget_instance_id"]) do
            nil -> []
            inst -> [Map.merge(cell, %{instance: inst})]
          end
        end)

      %{mode: "fullscreen_widget", layout: %{"widget_instance_id" => id}} ->
        case Widgets.get_instance(id) do
          nil -> []
          inst -> [%{"x" => 0, "y" => 0, "w" => 12, "h" => 12, instance: inst}]
        end

      _ ->
        []
    end
  end

  defp subscribe_scene(nil), do: :ok

  defp subscribe_scene(scene_id) do
    Phoenix.PubSub.subscribe(Kakemono.PubSub, "scene:#{scene_id}")
  end

  defp resubscribe_scene(socket, scene_id, scene_id), do: socket

  defp resubscribe_scene(socket, old_scene_id, new_scene_id) do
    unsubscribe_scene(old_scene_id)
    subscribe_scene(new_scene_id)
    socket
  end

  defp unsubscribe_scene(nil), do: :ok

  defp unsubscribe_scene(scene_id) do
    Phoenix.PubSub.unsubscribe(Kakemono.PubSub, "scene:#{scene_id}")
  end

  @impl true
  def handle_info({:scene_changed, scene_id}, socket) do
    if socket.assigns.override_scene do
      {:noreply, socket}
    else
      cells = load_scene_cells(scene_id)
      prefetch_cells(cells)

      {:noreply,
       socket
       |> resubscribe_scene(socket.assigns.scene && socket.assigns.scene.id, scene_id)
       |> assign(:scene, load_scene(scene_id))
       |> assign(:scene_cells, cells)}
    end
  end

  def handle_info({:scene_updated, scene_id}, socket) do
    current_id = socket.assigns.scene && socket.assigns.scene.id

    if current_id == scene_id do
      cells = load_scene_cells(scene_id)
      prefetch_cells(cells)

      {:noreply,
       socket
       |> assign(:scene, load_scene(scene_id))
       |> assign(:scene_cells, cells)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:widget_config_updated, %{instance_id: _id}}, socket) do
    sid = socket.assigns.scene && socket.assigns.scene.id
    {:noreply, assign(socket, :scene_cells, load_scene_cells(sid))}
  end

  def handle_info({:playlist_updated, %{playlist_id: pid}}, socket) do
    socket =
      Enum.reduce(socket.assigns.scene_cells, socket, fn cell, acc ->
        inst = cell.instance

        if inst.widget_type == "slideshow" and inst.config["playlist_id"] == pid do
          {pl, items} = Slideshow.items_for(inst)
          fit = Slideshow.fit_mode(inst, pl)

          push_event(acc, "slideshow:update", %{instance_id: inst.id, items: items, fit_mode: fit})
        else
          acc
        end
      end)

    {:noreply, socket}
  end

  def handle_info({:fully_kiosk_cmd, cmd}, socket) do
    {:noreply, push_event(socket, "fully_kiosk", %{cmd: cmd})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @scene do %>
      <.scene_view
        scene={@scene}
        cells={@scene_cells}
        display_id={@display_id}
        preview_weather={@preview_weather}
      />
    <% else %>
      <.empty_view display_id={@display_id} display_name={@display_name} />
    <% end %>
    """
  end

  attr :scene, :map, required: true
  attr :cells, :list, required: true
  attr :display_id, :string, required: true
  attr :preview_weather, :map, default: nil

  defp scene_view(assigns) do
    ~H"""
    <div
      id={"scene-" <> @display_id}
      class={scene_shell_class(@scene)}
      phx-hook="WakeLock"
    >
      <div
        class={scene_board_class(@scene)}
        style={scene_board_style(@scene)}
      >
        <div
          :for={cell <- @cells}
          id={"cell-#{cell.instance.id}"}
          class={[
            "kw-card",
            "kw-card-" <> cell.instance.widget_type,
            @scene.mode == "fullscreen_widget" && "kw-card-fullscreen"
          ]}
          data-widget-type={cell.instance.widget_type}
          style={cell_style(cell)}
        >
          <div class="kw-card-inner">
            {render_widget(cell.instance, @preview_weather)}
          </div>
        </div>

        <div
          :if={@cells == []}
          class="col-span-12 row-span-12 flex items-center justify-center text-2xl opacity-60"
        >
          Scene "{@scene.name}" has no widgets yet.
        </div>
      </div>
    </div>
    """
  end

  attr :display_id, :string, required: true
  attr :display_name, :string, required: true

  defp empty_view(assigns) do
    ~H"""
    <div
      id={"display-" <> @display_id}
      class="fixed inset-0 bg-black overflow-hidden text-white flex items-center justify-center p-8"
      phx-hook="WakeLock"
    >
      <div class="max-w-2xl w-full text-center space-y-4 bg-white/5 border border-white/10 rounded-2xl p-10">
        <div class="text-sm uppercase tracking-widest text-white/50">Kakemono Display</div>
        <h1 class="text-5xl font-bold">{@display_name}</h1>
        <div class="text-white/60 text-lg">
          id: <code class="font-mono">{@display_id}</code>
        </div>
        <p class="text-white/70 text-lg">
          No scene assigned. Open <code class="font-mono bg-white/10 px-2 py-0.5 rounded">/c</code>
          to pick a scene, or build one at <code class="font-mono bg-white/10 px-2 py-0.5 rounded">/c/scenes</code>.
        </p>
      </div>
    </div>
    """
  end

  defp cell_style(%{"x" => x, "y" => y, "w" => w, "h" => h}) do
    "grid-column: #{x + 1} / span #{w}; grid-row: #{y + 1} / span #{h};"
  end

  defp scene_shell_class(%{color_scheme: "light"}) do
    "kw-shell kw-shell-light fixed inset-0 overflow-hidden text-slate-950 flex items-center justify-center"
  end

  defp scene_shell_class(_) do
    "kw-shell kw-shell-dark fixed inset-0 overflow-hidden text-white flex items-center justify-center"
  end

  defp scene_board_class(%{color_scheme: "light"}) do
    "kw-board kw-board-light grid overflow-hidden"
  end

  defp scene_board_class(_) do
    "kw-board kw-board-dark grid overflow-hidden"
  end

  defp scene_board_style(scene) do
    {w, h} = scene_dimensions(scene)

    "grid-template-columns: repeat(12, 1fr); grid-template-rows: repeat(12, 1fr); " <>
      "aspect-ratio: #{w} / #{h}; width: min(100vw, calc(100vh * #{w} / #{h})); " <>
      "height: min(100vh, calc(100vw * #{h} / #{w}));"
  end

  defp scene_dimensions(%{aspect_ratio: ratio, orientation: orientation}) do
    [w, h] =
      ratio
      |> String.split(":")
      |> Enum.map(&String.to_integer/1)

    cond do
      orientation == "portrait" and w > h -> {h, w}
      orientation == "landscape" and h > w -> {h, w}
      true -> {w, h}
    end
  rescue
    _ -> {9, 16}
  end

  defp render_widget(%Kakemono.Widgets.Instance{widget_type: type} = inst, preview_weather) do
    case Kakemono.Widgets.Registry.fetch(type) do
      nil ->
        assigns = %{type: type}

        ~H"""
        <div class="flex items-center justify-center text-red-500">Unknown widget: {@type}</div>
        """

      mod ->
        mod.render(%{instance: apply_weather_preview(inst, preview_weather)})
    end
  end

  defp weather_preview(params) do
    cond = normalize_weather_cond(params["weather_cond"])
    tod = normalize_weather_tod(params["weather_tod"])

    if cond || tod, do: %{cond: cond, tod: tod}, else: nil
  end

  defp normalize_weather_cond(value)
       when value in ~w(clear partly cloudy fog drizzle rain showers snow thunder),
       do: value

  defp normalize_weather_cond(_), do: nil

  defp normalize_weather_tod(value) when value in ~w(day dawn dusk night), do: value
  defp normalize_weather_tod(_), do: nil

  defp apply_weather_preview(inst, nil), do: inst

  defp apply_weather_preview(%Kakemono.Widgets.Instance{widget_type: type} = inst, _preview)
       when type != "weather",
       do: inst

  defp apply_weather_preview(%Kakemono.Widgets.Instance{} = inst, preview) do
    cfg =
      inst.config
      |> maybe_put_preview("__preview_cond", preview[:cond])
      |> maybe_put_preview("__preview_tod", preview[:tod])

    %{inst | config: cfg}
  end

  defp maybe_put_preview(config, _key, nil), do: config
  defp maybe_put_preview(config, key, value), do: Map.put(config, key, value)
end
