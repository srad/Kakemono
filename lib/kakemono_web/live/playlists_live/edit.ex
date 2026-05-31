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
    |> assign(:active_nav, :playlists)
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
      |> put_flash(:info, ngettext("Uploaded 1 file", "Uploaded %{count} files", length(items)))
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

        {:noreply, put_flash(socket, :error, gettext("Invalid settings: %{msg}", msg: msg))}
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
    <div class="space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <.link
            navigate={~p"/c/playlists"}
            class="inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> {gettext("Playlists")}
          </.link>
          <h1 class="mt-1 text-2xl font-semibold tracking-tight text-slate-950">
            {@playlist.name}
          </h1>
        </div>
        <p class="text-sm text-slate-500">{ngettext("1 entry", "%{count} entries", length(@playlist.entries))}</p>
      </div>

      <form
        phx-change="update_settings"
        class="rounded-lg border border-slate-200 bg-white p-5 text-sm shadow-sm"
      >
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-slate-950">{gettext("Playback settings")}</h2>
          <p class="text-sm text-slate-500">{gettext("Control how playlist media fits the display.")}</p>
        </div>
        <div class="flex flex-wrap items-center gap-4">
          <div class="flex items-center gap-2">
            <label for="fit-mode" class="font-medium text-slate-700">{gettext("Display fit")}</label>
            <select
              id="fit-mode"
              name="fit_mode"
              class="rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            >
              <option
                :for={mode <- Kakemono.Playlists.Playlist.fit_modes()}
                value={mode}
                selected={mode == @playlist.fit_mode}
              >
                {mode}
              </option>
            </select>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <label for="transition-duration" class="font-medium text-slate-700">
              {gettext("Transition (ms)")}
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
              class="w-28 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
              phx-debounce="500"
            />
            <span class="text-slate-500">
              blank = use each item’s own duration (videos: natural length, images: 6000ms)
            </span>
          </div>
        </div>

        <p class="mt-3 text-xs text-slate-500">
          contain = letterbox; cover = fill &amp; crop; fill = stretch; scale-down = native or fit; none = native
        </p>
      </form>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <section class="rounded-lg border border-slate-200 bg-white shadow-sm">
          <div class="border-b border-slate-200 px-5 py-4">
            <h2 class="font-semibold text-slate-950">{gettext("Entries")}</h2>
            <p class="text-sm text-slate-500">{gettext("Drag to reorder the playback sequence.")}</p>
          </div>
          <ul id="entries" phx-hook="Sortable" class="divide-y divide-slate-200">
            <li
              :for={e <- @playlist.entries}
              id={"entry-#{e.id}"}
              data-id={e.id}
              class="flex cursor-move items-center gap-3 px-5 py-3 transition hover:bg-slate-50"
            >
              <span class="w-6 text-center text-slate-400">≡</span>
              <%= if e.media_item.thumbnail_path do %>
                <img src={Media.thumb_url(e.media_item)} class="w-16 h-16 object-cover rounded" />
              <% else %>
                <div class="flex h-16 w-16 items-center justify-center rounded bg-slate-100 text-[10px] text-slate-500">
                  {e.media_item.status}
                </div>
              <% end %>
              <div class="flex-1 truncate text-sm font-medium text-slate-800">
                {e.media_item.original_filename}
              </div>
              <button
                phx-click="remove"
                phx-value-entry_id={e.id}
                class="rounded-md px-2.5 py-1.5 text-sm font-medium text-rose-600 transition hover:bg-rose-50"
              >
                {gettext("remove")}
              </button>
            </li>
            <li :if={@playlist.entries == []} class="px-5 py-8 text-center text-sm text-slate-500">
              {gettext("No entries yet — upload below or pick from the library.")}
            </li>
          </ul>
        </section>

        <section class="space-y-5">
          <form
            id="playlist-upload"
            phx-submit="save"
            phx-change="validate"
            class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm"
          >
            <h2 class="mb-1 font-semibold text-slate-950">{gettext("Upload & auto-add to this playlist")}</h2>
            <p class="mb-4 text-sm text-slate-500">
              New files are added here after upload and processing.
            </p>
            <.live_file_input
              upload={@uploads.files}
              class="block w-full rounded-md border border-dashed border-slate-300 bg-slate-50 p-4 text-sm text-slate-600"
            />
            <ul class="mt-4 space-y-2 text-sm">
              <li :for={entry <- @uploads.files.entries} class="flex items-center gap-2">
                <span class="flex-1 truncate text-slate-700">{entry.client_name}</span>
                <div class="h-2 w-32 overflow-hidden rounded-full bg-slate-200">
                  <div class="h-full bg-slate-950" style={"width: #{entry.progress}%"} />
                </div>
                <span class="w-10 text-right tabular-nums text-slate-500">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="rounded px-2 py-1 text-xs font-medium text-rose-600 hover:bg-rose-50"
                >
                  cancel
                </button>
              </li>
              <li :for={err <- upload_errors(@uploads.files)} class="text-rose-600">
                {inspect(err)}
              </li>
            </ul>
            <p class="mt-3 text-xs text-slate-500">
              Uploads start automatically when you pick files. They are transcoded in the background and added to this playlist.
            </p>
          </form>

          <section class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
            <h2 class="mb-3 font-semibold text-slate-950">{gettext("Or add existing media")}</h2>
            <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-4">
              <button
                :for={m <- @available_media}
                phx-click="add"
                phx-value-media_id={m.id}
                class="overflow-hidden rounded-lg border border-slate-200 bg-white text-left shadow-sm transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md"
              >
                <div class="aspect-square bg-slate-100">
                  <%= if m.thumbnail_path do %>
                    <img src={Media.thumb_url(m)} class="w-full h-full object-cover" />
                  <% end %>
                </div>
                <div class="truncate p-2 text-xs font-medium text-slate-700">
                  {m.original_filename}
                </div>
              </button>
              <p :if={@available_media == []} class="col-span-full text-sm text-slate-500">
                {gettext("No ready media in the library yet.")}
              </p>
            </div>
          </section>
        </section>
      </div>
    </div>
    """
  end
end
