defmodule KakemonoWeb.PlaylistsLive.Edit do
  use KakemonoWeb, :live_view
  alias Kakemono.{Playlists, Media}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Playlists.get_with_items(id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/c/playlists")}

      p ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Kakemono.PubSub, "media")

        {:ok,
         socket
         |> load(p)
         |> allow_upload(:files,
           accept: ~w(.jpg .jpeg .png .gif .webp .heic .heif .mp4 .mov .mkv .webm),
           max_entries: 20,
           max_file_size: 500_000_000,
           auto_upload: true,
           progress: &handle_progress/3
         )}
    end
  end

  defp load(socket, playlist) do
    socket
    |> assign(:page_title, playlist.name)
    |> assign(:playlist, playlist)
    |> assign(:available_media, Media.list_items() |> Enum.filter(&(&1.status == "ready")))
  end

  defp reload(socket) do
    load(socket, Playlists.get_with_items(socket.assigns.playlist.id))
  end

  defp handle_progress(:files, entry, socket) do
    if entry.done? and Enum.all?(socket.assigns.uploads.files.entries, & &1.done?) do
      {:noreply, consume_and_add(socket)}
    else
      {:noreply, socket}
    end
  end

  defp consume_and_add(socket) do
    playlist = socket.assigns.playlist

    items =
      consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
        case Media.upload(path, %{
               original_filename: entry.client_name,
               mime_type: entry.client_type
             }) do
          {:ok, item} ->
            _ = Playlists.add_item(playlist, item.id)
            {:ok, item}

          other ->
            {:postpone, other}
        end
      end)

    if items == [] do
      socket
    else
      socket
      |> assign(:playlist, Playlists.get_with_items(playlist.id))
      |> put_flash(:info, "Uploaded #{length(items)} file(s)")
    end
  end

  @impl true
  def handle_info({:media_updated, _item}, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info({:media_created, _item}, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info({:playlist_updated, _}, socket), do: {:noreply, reload(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket), do: {:noreply, consume_and_add(socket)}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("add", %{"media_id" => mid}, socket) do
    {:ok, _} = Playlists.add_item(socket.assigns.playlist, String.to_integer(mid))
    {:noreply, reload(socket)}
  end

  def handle_event("remove", %{"entry_id" => eid}, socket) do
    :ok = Playlists.remove_entry(String.to_integer(eid))
    {:noreply, reload(socket)}
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    int_ids = Enum.map(ids, &String.to_integer/1)
    :ok = Playlists.reorder(socket.assigns.playlist.id, int_ids)
    {:noreply, reload(socket)}
  end

  def handle_event("update_settings", params, socket) do
    attrs =
      %{}
      |> maybe_put(:fit_mode, params["fit_mode"] || :skip)
      |> maybe_put(:transition_duration_ms, parse_duration(params["transition_duration_ms"]))

    case Playlists.update_settings(socket.assigns.playlist, attrs) do
      {:ok, _} ->
        {:noreply, reload(socket)}

      {:error, cs} ->
        msg =
          cs.errors
          |> Enum.map_join("; ", fn {field, {m, _}} -> "#{field} #{m}" end)

        {:noreply, put_flash(socket, :error, "Invalid settings: " <> msg)}
    end
  end

  defp maybe_put(map, _k, :skip), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  # nil  -> param absent, skip
  # ""   -> explicit clear (use per-item duration)
  # "<n>"-> parsed integer
  defp parse_duration(nil), do: :skip
  defp parse_duration(""), do: nil

  defp parse_duration(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      :error -> :skip
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 w-full">
      <.link navigate={~p"/c/playlists"} class="text-sm text-blue-600">&larr; Playlists</.link>
      <h1 class="text-2xl font-bold mb-4">{@playlist.name}</h1>

      <form phx-change="update_settings" class="flex flex-wrap items-center gap-4 mb-6 text-sm">
        <div class="flex items-center gap-2">
          <label for="fit-mode" class="font-medium text-gray-700">Display fit:</label>
          <select id="fit-mode" name="fit_mode" class="border rounded px-2 py-1">
            <option
              :for={mode <- Kakemono.Playlists.Playlist.fit_modes()}
              value={mode}
              selected={mode == @playlist.fit_mode}
            >
              {mode}
            </option>
          </select>
        </div>

        <div class="flex items-center gap-2">
          <label for="transition-duration" class="font-medium text-gray-700">
            Transition (ms):
          </label>
          <input
            id="transition-duration"
            type="number"
            name="transition_duration_ms"
            min="500"
            max="600000"
            step="500"
            placeholder="default"
            value={@playlist.transition_duration_ms}
            class="border rounded px-2 py-1 w-28"
            phx-debounce="500"
          />
          <span class="text-gray-500">
            blank = use each item’s own duration (videos: natural length, images: 6000ms)
          </span>
        </div>

        <span class="text-gray-500 basis-full">
          contain = letterbox; cover = fill &amp; crop; fill = stretch; scale-down = native or fit; none = native
        </span>
      </form>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <section>
          <h2 class="font-semibold mb-2">Entries (drag to reorder)</h2>
          <ul id="entries" phx-hook="Sortable" class="border rounded divide-y">
            <li
              :for={e <- @playlist.entries}
              id={"entry-#{e.id}"}
              data-id={e.id}
              class="flex items-center gap-3 p-2 bg-white cursor-move"
            >
              <span class="text-gray-400 w-6 text-center">≡</span>
              <%= if e.media_item.thumbnail_path do %>
                <img src={Media.thumb_url(e.media_item)} class="w-16 h-16 object-cover rounded" />
              <% else %>
                <div class="w-16 h-16 bg-gray-100 flex items-center justify-center text-[10px] text-gray-500">
                  {e.media_item.status}
                </div>
              <% end %>
              <div class="flex-1 truncate">{e.media_item.original_filename}</div>
              <button phx-click="remove" phx-value-entry_id={e.id} class="text-red-600 text-sm">
                remove
              </button>
            </li>
            <li :if={@playlist.entries == []} class="p-3 text-sm text-gray-500">
              No entries yet — upload below or pick from the library.
            </li>
          </ul>
        </section>

        <section>
          <h2 class="font-semibold mb-2">Upload &amp; auto-add to this playlist</h2>
          <form
            id="playlist-upload"
            phx-submit="save"
            phx-change="validate"
            class="border rounded p-4 mb-4 bg-gray-50"
          >
            <.live_file_input upload={@uploads.files} class="block mb-3" />
            <ul class="text-sm space-y-1">
              <li :for={entry <- @uploads.files.entries} class="flex items-center gap-2">
                <span class="truncate flex-1">{entry.client_name}</span>
                <div class="w-32 bg-gray-200 rounded h-2 overflow-hidden">
                  <div class="bg-blue-500 h-full" style={"width: #{entry.progress}%"} />
                </div>
                <span class="tabular-nums w-10 text-right">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="text-red-600 text-xs"
                >
                  cancel
                </button>
              </li>
              <li :for={err <- upload_errors(@uploads.files)} class="text-red-600">
                {inspect(err)}
              </li>
            </ul>
            <p class="mt-2 text-xs text-gray-500">
              Uploads start automatically when you pick files. They are transcoded in the background and added to this playlist.
            </p>
          </form>

          <h2 class="font-semibold mb-2">Or add existing media</h2>
          <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-3">
            <button
              :for={m <- @available_media}
              phx-click="add"
              phx-value-media_id={m.id}
              class="border rounded overflow-hidden hover:ring-2 ring-primary text-left"
            >
              <div class="aspect-square bg-gray-100">
                <%= if m.thumbnail_path do %>
                  <img src={Media.thumb_url(m)} class="w-full h-full object-cover" />
                <% end %>
              </div>
              <div class="p-1 text-xs truncate">{m.original_filename}</div>
            </button>
            <p :if={@available_media == []} class="text-sm text-gray-500 col-span-full">
              No ready media in the library yet.
            </p>
          </div>
        </section>
      </div>
    </div>
    """
  end
end
