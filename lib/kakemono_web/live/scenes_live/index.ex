defmodule KakemonoWeb.ScenesLive.Index do
  use KakemonoWeb, :live_view
  alias Kakemono.Scenes

  @modes ~w(dashboard fullscreen_widget)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       scenes: Scenes.list(),
       modes: @modes,
       aspect_ratios: Kakemono.Scenes.Scene.aspect_ratios(),
       orientations: Kakemono.Scenes.Scene.orientations(),
       color_schemes: Kakemono.Scenes.Scene.color_schemes(),
       form_error: nil
     )}
  end

  @impl true
  def handle_event("create_scene", %{"scene" => params}, socket) do
    name = Map.get(params, "name", "")
    mode = Map.get(params, "mode", "dashboard")
    ratio = Map.get(params, "aspect_ratio", "16:9")
    orientation = Map.get(params, "orientation", "portrait")
    color_scheme = Map.get(params, "color_scheme", "light")

    layout =
      case mode do
        "dashboard" -> %{"cells" => []}
        "fullscreen_widget" -> %{"widget_instance_id" => 0}
        _ -> %{"cells" => []}
      end

    case Scenes.create(%{
           name: String.trim(name),
           mode: mode,
           layout: layout,
           aspect_ratio: ratio,
           orientation: orientation,
           color_scheme: color_scheme
         }) do
      {:ok, p} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scene '#{p.name}' created")
         |> assign(:scenes, Scenes.list())
         |> assign(:form_error, nil)}

      {:error, cs} ->
        {:noreply, assign(socket, :form_error, format_errors(cs))}
    end
  end

  def handle_event("delete_scene", %{"id" => id}, socket) do
    case Scenes.get(String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      p ->
        {:ok, _} = Scenes.delete(p)
        {:noreply, assign(socket, :scenes, Scenes.list())}
    end
  end

  defp format_errors(cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map(fn {k, msgs} -> "#{k}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6 w-full">
      <h1 class="text-2xl font-bold">Scenes</h1>
      <nav class="flex gap-4 text-blue-600">
        <.link navigate={~p"/c"}>Back to Control</.link>
        <.link navigate={~p"/c/media"}>Media</.link>
        <.link navigate={~p"/c/playlists"}>Playlists</.link>
      </nav>

      <form
        id="create-scene-form"
        phx-submit="create_scene"
        class="flex flex-wrap items-end gap-2 p-3 border rounded bg-white shadow-sm"
      >
        <div>
          <label class="block text-xs text-gray-500">Name</label>
          <input type="text" name="scene[name]" required class="border rounded px-2 py-1" />
        </div>
        <div>
          <label class="block text-xs text-gray-500">Mode</label>
          <select name="scene[mode]" class="border rounded px-2 py-1">
            <option :for={m <- @modes} value={m}>{m}</option>
          </select>
        </div>
        <div>
          <label class="block text-xs text-gray-500">Aspect Ratio</label>
          <select name="scene[aspect_ratio]" class="border rounded px-2 py-1">
            <option :for={r <- @aspect_ratios} value={r}>{r}</option>
          </select>
        </div>
        <div>
          <label class="block text-xs text-gray-500">Orientation</label>
          <select name="scene[orientation]" class="border rounded px-2 py-1">
            <option :for={o <- @orientations} value={o} selected={o == "portrait"}>{o}</option>
          </select>
        </div>
        <div>
          <label class="block text-xs text-gray-500">Theme</label>
          <select name="scene[color_scheme]" class="border rounded px-2 py-1">
            <option :for={s <- @color_schemes} value={s} selected={s == "light"}>{s}</option>
          </select>
        </div>
        <button type="submit" class="bg-primary text-primary-foreground px-3 py-1.5 rounded">
          Create
        </button>
        <p :if={@form_error} class="text-red-600 text-sm w-full">{@form_error}</p>
      </form>

      <ul id="scenes-list" class="space-y-2">
        <li
          :for={p <- @scenes}
          id={"scene-#{p.id}"}
          class="flex items-center gap-3 p-3 border rounded"
        >
          <.link navigate={~p"/c/scenes/#{p.id}"} class="font-medium hover:underline">{p.name}</.link>
          <span class="text-sm text-gray-500">{p.mode}</span>
          <button
            phx-click="delete_scene"
            phx-value-id={p.id}
            data-confirm={"Delete scene '#{p.name}'?"}
            class="ml-auto text-red-600 text-sm hover:underline"
          >
            delete
          </button>
        </li>
      </ul>

      <p :if={@scenes == []} class="text-gray-500">No scenes yet. Create one above.</p>
    </div>
    """
  end
end
