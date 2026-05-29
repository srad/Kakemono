defmodule KakemonoWeb.ControlLive.Index do
  use KakemonoWeb, :live_view

  alias Kakemono.{Displays, Scenes}
  alias KakemonoWeb.{FullyKiosk, Presence}

  @id_regex ~r/^[a-z0-9_-]+$/

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "displays")
      Phoenix.PubSub.subscribe(Kakemono.PubSub, Presence.topic())
    end

    {:ok,
     socket
     |> assign(:page_title, "Control")
     |> assign(:active_nav, :control)
     |> assign_state()}
  end

  @impl true
  def handle_info({:display_updated, _d}, socket), do: {:noreply, assign_state(socket)}
  def handle_info({:display_deleted, _id}, socket), do: {:noreply, assign_state(socket)}
  def handle_info(%{event: "presence_diff"}, socket), do: {:noreply, assign_state(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_scene", %{"display_id" => did, "scene_id" => pid}, socket) do
    scene_id =
      case pid do
        "" -> nil
        nil -> nil
        s when is_binary(s) -> String.to_integer(s)
      end

    case Displays.set_scene(did, scene_id) do
      {:ok, _} -> {:noreply, assign_state(socket)}
      :error -> {:noreply, put_flash(socket, :error, "Display not found")}
    end
  end

  def handle_event("fk_cmd", %{"display_id" => did, "cmd" => cmd}, socket) do
    FullyKiosk.broadcast(did, cmd)
    {:noreply, socket}
  end

  def handle_event("delete_display", %{"id" => id}, socket) do
    case Displays.delete(id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Display '#{id}' deleted") |> assign_state()}

      :error ->
        {:noreply, put_flash(socket, :error, "Display not found")}
    end
  end

  def handle_event("create_display", %{"display" => %{"id" => id, "name" => name}}, socket) do
    id = String.trim(id)
    name = name |> to_string() |> String.trim()
    name = if name == "", do: humanize(id), else: name

    cond do
      not Regex.match?(@id_regex, id) ->
        {:noreply, put_flash(socket, :error, "ID must match a-z, 0-9, _ or -")}

      Displays.get(id) ->
        {:noreply, put_flash(socket, :error, "Display '#{id}' already exists")}

      true ->
        case Displays.create(%{id: id, name: name}) do
          {:ok, _d} ->
            {:noreply, socket |> put_flash(:info, "Display '#{id}' created") |> assign_state()}

          {:error, _cs} ->
            {:noreply, put_flash(socket, :error, "Could not create display")}
        end
    end
  end

  defp humanize(id) do
    id
    |> String.replace(["-", "_"], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp assign_state(socket) do
    presence_ids = MapSet.new(Presence.online_display_ids())
    displays = Displays.list()
    scenes = Scenes.list()

    assign(socket, displays: displays, presence_ids: presence_ids, scenes: scenes)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p class="text-sm font-medium text-slate-500">Backend</p>
          <h1 class="text-2xl font-semibold tracking-tight text-slate-950">Kakemono Control</h1>
        </div>
        <p class="text-sm text-slate-500">
          {length(@displays)} displays · {length(@scenes)} scenes
        </p>
      </div>

      <section class="rounded-lg border border-slate-200 bg-white shadow-sm">
        <div class="flex items-center justify-between border-b border-slate-200 px-5 py-4">
          <div>
            <h2 class="text-lg font-semibold text-slate-950">Displays</h2>
            <p class="text-sm text-slate-500">
              Register screens, assign scenes, and control connected kiosks.
            </p>
          </div>
        </div>

        <form
          id="create-display-form"
          phx-submit="create_display"
          class="grid gap-3 border-b border-slate-200 bg-slate-50/70 p-5 md:grid-cols-[minmax(10rem,14rem)_minmax(14rem,1fr)_auto]"
        >
          <div>
            <label class="mb-1 block text-xs font-medium uppercase tracking-wide text-slate-500">
              ID
            </label>
            <input
              type="text"
              name="display[id]"
              placeholder="tablet"
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
              required
            />
          </div>
          <div>
            <label class="mb-1 block text-xs font-medium uppercase tracking-wide text-slate-500">
              Name
            </label>
            <input
              type="text"
              name="display[name]"
              placeholder="Living-room tablet"
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            />
          </div>
          <button
            type="submit"
            class="inline-flex h-10 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800"
          >
            Add display
          </button>
          <p class="text-xs text-slate-500 md:col-span-3">
            Or just visit <code>/d/&lt;id&gt;</code> — the display is auto-registered on first load.
          </p>
        </form>

        <ul id="displays-list" class="divide-y divide-slate-200">
          <li
            :for={d <- @displays}
            id={"display-#{d.id}"}
            class="flex flex-col gap-4 px-5 py-4 lg:flex-row lg:items-center"
          >
            <div class="flex min-w-0 items-center gap-3">
              <span
                class={[
                  "h-2.5 w-2.5 rounded-full ring-4",
                  if(online?(d, @presence_ids),
                    do: "bg-emerald-500 ring-emerald-100",
                    else: "bg-rose-500 ring-rose-100"
                  )
                ]}
                data-state={if online?(d, @presence_ids), do: "online", else: "offline"}
                data-display-id={d.id}
              />
              <div class="min-w-0">
                <.link
                  navigate={~p"/d/#{d.id}"}
                  class="truncate font-medium text-slate-950 hover:text-slate-700"
                >
                  {d.name}
                </.link>
                <div class="truncate text-sm text-slate-500">/d/{d.id}</div>
              </div>
            </div>

            <div class="flex flex-1 flex-wrap items-center gap-3 text-sm lg:justify-end">
              <form
                phx-change="set_scene"
                class="flex min-w-0 items-center gap-2"
                id={"scene-form-#{d.id}"}
              >
                <input type="hidden" name="display_id" value={d.id} />
                <label for={"pr-#{d.id}"} class="text-slate-600">Scene</label>
                <select
                  id={"pr-#{d.id}"}
                  name="scene_id"
                  class="min-w-36 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                  data-display-id={d.id}
                >
                  <option value="" selected={is_nil(d.current_scene_id)}>— none —</option>
                  <option
                    :for={p <- @scenes}
                    value={p.id}
                    selected={d.current_scene_id == p.id}
                  >
                    {p.name}
                  </option>
                </select>
              </form>

              <div :if={present?(d, @presence_ids)} class="flex gap-1">
                <button
                  phx-click="fk_cmd"
                  phx-value-display_id={d.id}
                  phx-value-cmd="screenOn"
                  class="rounded-md border border-slate-200 px-2.5 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-50"
                  title="Wake screen"
                >
                  Wake
                </button>
                <button
                  phx-click="fk_cmd"
                  phx-value-display_id={d.id}
                  phx-value-cmd="screenOff"
                  class="rounded-md border border-slate-200 px-2.5 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-50"
                  title="Sleep screen"
                >
                  Sleep
                </button>
                <button
                  phx-click="fk_cmd"
                  phx-value-display_id={d.id}
                  phx-value-cmd="reloadPage"
                  class="rounded-md border border-slate-200 px-2.5 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-50"
                  title="Reload display page"
                >
                  Refresh
                </button>
                <button
                  phx-click="fk_cmd"
                  phx-value-display_id={d.id}
                  phx-value-cmd="restartApp"
                  class="rounded-md border border-slate-200 px-2.5 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-50"
                  title="Restart Fully Kiosk"
                >
                  Restart
                </button>
              </div>

              <button
                phx-click="delete_display"
                phx-value-id={d.id}
                data-confirm={"Delete display '#{d.name}'?"}
                class="rounded-md px-2.5 py-1.5 text-xs font-medium text-rose-600 transition hover:bg-rose-50"
              >
                delete
              </button>
            </div>
          </li>
        </ul>

        <p :if={@displays == []} class="px-5 py-8 text-center text-sm text-slate-500">
          No displays registered yet. Add one above or visit <code>/d/&lt;id&gt;</code>.
        </p>
      </section>
    </div>
    """
  end

  defp online?(d, presence_ids) do
    MapSet.member?(presence_ids, d.id) or Displays.online?(d)
  end

  defp present?(d, presence_ids) do
    MapSet.member?(presence_ids, d.id)
  end
end
