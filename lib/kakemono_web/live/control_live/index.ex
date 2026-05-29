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

    {:ok, assign_state(socket)}
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
    <div class="p-6 space-y-6 w-full">
      <h1 class="text-2xl font-bold">Kakemono Control</h1>

      <nav class="flex gap-4 text-blue-600">
        <.link navigate={~p"/c/media"}>Media</.link>
        <.link navigate={~p"/c/playlists"}>Playlists</.link>
        <.link navigate={~p"/c/scenes"}>Scenes</.link>
        <.link navigate={~p"/c/settings"}>Settings</.link>
        <.link navigate={~p"/c/backups"}>Backups</.link>
      </nav>

      <section>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-xl font-semibold">Displays</h2>
        </div>

        <form
          id="create-display-form"
          phx-submit="create_display"
          class="flex flex-wrap items-end gap-2 mb-4 p-3 border rounded bg-white shadow-sm"
        >
          <div>
            <label class="block text-xs text-gray-500">ID</label>
            <input
              type="text"
              name="display[id]"
              placeholder="tablet"
              class="border rounded px-2 py-1"
              required
            />
          </div>
          <div>
            <label class="block text-xs text-gray-500">Name (optional)</label>
            <input
              type="text"
              name="display[name]"
              placeholder="Living-room tablet"
              class="border rounded px-2 py-1"
            />
          </div>
          <button type="submit" class="bg-primary text-primary-foreground px-3 py-1.5 rounded">
            Add display
          </button>
          <p class="text-xs text-gray-500 ml-2 w-full">
            Or just visit <code>/d/&lt;id&gt;</code> — the display is auto-registered on first load.
          </p>
        </form>

        <ul id="displays-list" class="space-y-2">
          <li
            :for={d <- @displays}
            id={"display-#{d.id}"}
            class="flex items-center gap-3 p-3 border rounded"
          >
            <span
              class={[
                "inline-block w-3 h-3 rounded-full",
                if(online?(d, @presence_ids), do: "bg-green-500", else: "bg-red-500")
              ]}
              data-state={if online?(d, @presence_ids), do: "online", else: "offline"}
              data-display-id={d.id}
            />

            <.link navigate={~p"/d/#{d.id}"} class="font-medium hover:underline">
              {d.name}
            </.link>
            <span class="text-sm text-gray-500">/d/{d.id}</span>

            <div class="ml-auto flex items-center gap-3 text-sm flex-wrap justify-end">
              <form
                phx-change="set_scene"
                class="flex items-center gap-2"
                id={"scene-form-#{d.id}"}
              >
                <input type="hidden" name="display_id" value={d.id} />
                <label for={"pr-#{d.id}"} class="text-gray-600">Scene:</label>
                <select
                  id={"pr-#{d.id}"}
                  name="scene_id"
                  class="border rounded px-2 py-1"
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
                  class="border rounded px-2 py-1 text-xs hover:bg-gray-50"
                  title="Wake screen"
                >
                  Wake
                </button>
                <button
                  phx-click="fk_cmd"
                  phx-value-display_id={d.id}
                  phx-value-cmd="screenOff"
                  class="border rounded px-2 py-1 text-xs hover:bg-gray-50"
                  title="Sleep screen"
                >
                  Sleep
                </button>
                <button
                  phx-click="fk_cmd"
                  phx-value-display_id={d.id}
                  phx-value-cmd="reloadPage"
                  class="border rounded px-2 py-1 text-xs hover:bg-gray-50"
                  title="Reload display page"
                >
                  Refresh
                </button>
                <button
                  phx-click="fk_cmd"
                  phx-value-display_id={d.id}
                  phx-value-cmd="restartApp"
                  class="border rounded px-2 py-1 text-xs hover:bg-gray-50"
                  title="Restart Fully Kiosk"
                >
                  Restart
                </button>
              </div>

              <button
                phx-click="delete_display"
                phx-value-id={d.id}
                data-confirm={"Delete display '#{d.name}'?"}
                class="text-red-600 text-xs hover:underline"
              >
                delete
              </button>
            </div>
          </li>
        </ul>

        <p :if={@displays == []} class="text-gray-500">
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
