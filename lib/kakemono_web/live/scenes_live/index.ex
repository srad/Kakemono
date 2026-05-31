defmodule KakemonoWeb.ScenesLive.Index do
  use KakemonoWeb, :live_view
  alias Kakemono.Scenes

  @modes ~w(dashboard fullscreen_widget)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Scenes"),
       active_nav: :scenes,
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
         |> put_flash(:info, gettext("Scene '%{name}' created", name: p.name))
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
    <div class="space-y-6">
      <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p class="text-sm font-medium text-slate-500">{gettext("Layouts")}</p>
          <h1 class="text-2xl font-semibold tracking-tight text-slate-950">{gettext("Scenes")}</h1>
        </div>
        <p class="text-sm text-slate-500">{ngettext("1 scene", "%{count} scenes", length(@scenes))}</p>
      </div>

      <form
        id="create-scene-form"
        phx-submit="create_scene"
        class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm"
      >
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-slate-950">{gettext("Create scene")}</h2>
          <p class="text-sm text-slate-500">{gettext("Scenes define what each display shows.")}</p>
        </div>
        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-[minmax(14rem,1fr)_repeat(4,minmax(9rem,11rem))_auto]">
          <div>
            <label class="mb-1 block text-xs font-medium uppercase tracking-wide text-slate-500">
              {gettext("Name")}
            </label>
            <input
              type="text"
              name="scene[name]"
              required
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            />
          </div>
          <div>
            <label class="mb-1 block text-xs font-medium uppercase tracking-wide text-slate-500">
              {gettext("Mode")}
            </label>
            <select
              name="scene[mode]"
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            >
              <option :for={m <- @modes} value={m}>{m}</option>
            </select>
          </div>
          <div>
            <label class="mb-1 block text-xs font-medium uppercase tracking-wide text-slate-500">
              {gettext("Aspect Ratio")}
            </label>
            <select
              name="scene[aspect_ratio]"
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            >
              <option :for={r <- @aspect_ratios} value={r}>{r}</option>
            </select>
          </div>
          <div>
            <label class="mb-1 block text-xs font-medium uppercase tracking-wide text-slate-500">
              {gettext("Orientation")}
            </label>
            <select
              name="scene[orientation]"
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            >
              <option :for={o <- @orientations} value={o} selected={o == "portrait"}>{o}</option>
            </select>
          </div>
          <div>
            <label class="mb-1 block text-xs font-medium uppercase tracking-wide text-slate-500">
              {gettext("Theme")}
            </label>
            <select
              name="scene[color_scheme]"
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            >
              <option :for={s <- @color_schemes} value={s} selected={s == "light"}>{s}</option>
            </select>
          </div>
          <button
            type="submit"
            class="inline-flex h-10 items-center justify-center self-end rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800"
          >
            {gettext("Create")}
          </button>
        </div>
        <p :if={@form_error} class="mt-3 text-sm text-rose-600">{@form_error}</p>
      </form>

      <ul
        id="scenes-list"
        class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm"
      >
        <li
          :for={p <- @scenes}
          id={"scene-#{p.id}"}
          class="flex items-center gap-3 border-b border-slate-200 px-5 py-4 last:border-b-0"
        >
          <div class="min-w-0 flex-1">
            <.link
              navigate={~p"/c/scenes/#{p.id}"}
              class="truncate font-medium text-slate-950 hover:text-slate-700"
            >
              {p.name}
            </.link>
            <div class="mt-1 flex flex-wrap gap-2 text-xs">
              <span class="rounded-full bg-slate-100 px-2 py-0.5 font-medium text-slate-600">
                {p.mode}
              </span>
              <span class="rounded-full bg-slate-100 px-2 py-0.5 font-medium text-slate-600">
                {p.aspect_ratio} {p.orientation}
              </span>
              <span class="rounded-full bg-slate-100 px-2 py-0.5 font-medium text-slate-600">
                {p.color_scheme}
              </span>
            </div>
          </div>
          <button
            phx-click="delete_scene"
            phx-value-id={p.id}
            data-confirm={gettext("Delete scene '%{name}'?", name: p.name)}
            class="rounded-md px-2.5 py-1.5 text-sm font-medium text-rose-600 transition hover:bg-rose-50"
          >
            {gettext("delete")}
          </button>
        </li>
      </ul>

      <p
        :if={@scenes == []}
        class="rounded-lg border border-dashed border-slate-300 bg-white px-5 py-10 text-center text-sm text-slate-500"
      >
        {gettext("No scenes yet. Create one above.")}
      </p>
    </div>
    """
  end
end
