defmodule KakemonoWeb.MediaLive.Index do
  use KakemonoWeb, :live_view
  alias Kakemono.Media

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Kakemono.PubSub, "media")

    items = Media.list_items()

    {:ok,
     socket
     |> assign(:page_title, "Media")
     |> assign(:item_count, length(items))
     |> stream(:items, items)
     |> allow_upload(:files,
       accept: ~w(.jpg .jpeg .png .gif .webp .heic .heif .mp4 .mov .mkv .webm),
       max_entries: 20,
       max_file_size: 500_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp handle_progress(:files, entry, socket) do
    if entry.done? and Enum.all?(socket.assigns.uploads.files.entries, & &1.done?) do
      {:noreply, consume_and_insert(socket)}
    else
      {:noreply, socket}
    end
  end

  defp consume_and_insert(socket) do
    items =
      consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
        case Media.upload(path, %{
               original_filename: entry.client_name,
               mime_type: entry.client_type
             }) do
          {:ok, item} -> {:ok, item}
          other -> {:postpone, other}
        end
      end)

    socket =
      Enum.reduce(items, socket, fn
        %Kakemono.Media.Item{} = it, s -> stream_insert(s, :items, it, at: 0)
        _, s -> s
      end)

    if items == [],
      do: socket,
      else: put_flash(socket, :info, "Uploaded #{length(items)} file(s)")
  end

  @impl true
  def handle_info({:media_updated, item}, socket) do
    {:noreply, stream_insert(socket, :items, item)}
  end

  def handle_info({:media_created, item}, socket) do
    {:noreply, socket |> stream_insert(:items, item, at: 0) |> update(:item_count, &(&1 + 1))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("save", _params, socket), do: {:noreply, consume_and_insert(socket)}

  def handle_event("delete", %{"id" => id}, socket) do
    item = Media.get_item!(id)
    {:ok, _} = Media.delete_item(item)
    {:noreply, socket |> stream_delete(:items, item) |> update(:item_count, &max(&1 - 1, 0))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 w-full">
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">Media Library</h1>
        <nav class="text-sm text-blue-600 flex gap-4">
          <.link navigate={~p"/c"}>Control</.link>
          <.link navigate={~p"/c/playlists"}>Playlists</.link>
        </nav>
      </div>

      <form
        id="upload-form"
        phx-submit="save"
        phx-change="validate"
        class="mb-6 border rounded p-4 bg-white shadow-sm"
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
            {error_to_string(err)}
          </li>
        </ul>
        <p class="text-xs text-gray-500 mt-2">
          Uploads start automatically when you pick files.
        </p>
      </form>

      <p :if={@item_count == 0} class="text-gray-500 text-sm mt-2">
        No media yet — upload something above.
      </p>

      <div
        id="items"
        phx-update="stream"
        class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-6 2xl:grid-cols-8 gap-3"
      >
        <div
          :for={{dom_id, item} <- @streams.items}
          id={dom_id}
          class="border rounded overflow-hidden bg-white"
        >
          <div class="aspect-square bg-gray-100 flex items-center justify-center">
            <%= if item.thumbnail_path do %>
              <img src={Media.thumb_url(item)} class="w-full h-full object-cover" />
            <% else %>
              <span class="text-xs text-gray-500">{item.status}</span>
            <% end %>
          </div>
          <div class="p-2 text-xs">
            <div class="truncate">{item.original_filename}</div>
            <div class="flex justify-between items-center mt-1">
              <span class={status_class(item.status)}>{item.status}</span>
              <button
                phx-click="delete"
                phx-value-id={item.id}
                data-confirm="Delete this item?"
                class="text-red-600 hover:underline"
              >
                delete
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_class("ready"), do: "text-green-600"
  defp status_class("failed"), do: "text-red-600"
  defp status_class(_), do: "text-gray-500"

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:not_accepted), do: "Unsupported file type"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(other), do: inspect(other)
end
