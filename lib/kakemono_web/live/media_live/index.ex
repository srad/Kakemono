defmodule KakemonoWeb.MediaLive.Index do
  use KakemonoWeb, :live_view
  alias Kakemono.Media

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Kakemono.PubSub, "media")

    items = Media.list_items()

    {:ok,
     socket
     |> assign(:page_title, gettext("Media"))
     |> assign(:active_nav, :media)
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
      else: put_flash(socket, :info, ngettext("Uploaded 1 file", "Uploaded %{count} files", length(items)))
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
    <div class="space-y-6">
      <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p class="text-sm font-medium text-slate-500">{gettext("Assets")}</p>
          <h1 class="text-2xl font-semibold tracking-tight text-slate-950">{gettext("Media Library")}</h1>
        </div>
        <p class="text-sm text-slate-500">{ngettext("1 item", "%{count} items", @item_count)}</p>
      </div>

      <form
        id="upload-form"
        phx-submit="save"
        phx-change="validate"
        class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm"
      >
        <div class="mb-4 flex flex-col gap-1">
          <h2 class="text-lg font-semibold text-slate-950">{gettext("Upload media")}</h2>
          <p class="text-sm text-slate-500">
            {gettext("Images and videos are added to the library and processed in the background.")}
          </p>
        </div>
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
              {gettext("cancel")}
            </button>
          </li>
          <li :for={err <- upload_errors(@uploads.files)} class="text-rose-600">
            {error_to_string(err)}
          </li>
        </ul>
        <p class="mt-3 text-xs text-slate-500">
          {gettext("Uploads start automatically when you pick files.")}
        </p>
      </form>

      <div
        id="items"
        phx-update="stream"
        class="grid grid-cols-2 gap-4 md:grid-cols-4 xl:grid-cols-6 2xl:grid-cols-8"
      >
        <div
          :for={{dom_id, item} <- @streams.items}
          id={dom_id}
          class="group overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
        >
          <div class="flex aspect-square items-center justify-center bg-slate-100">
            <%= if item.thumbnail_path do %>
              <img src={Media.thumb_url(item)} class="w-full h-full object-cover" />
            <% else %>
              <span class="text-xs font-medium text-slate-500">{item.status}</span>
            <% end %>
          </div>
          <div class="space-y-2 p-3 text-xs">
            <div class="truncate font-medium text-slate-800" title={item.original_filename}>
              {item.original_filename}
            </div>
            <div class="flex items-center justify-between">
              <span class={status_class(item.status)}>{item.status}</span>
              <button
                phx-click="delete"
                phx-value-id={item.id}
                data-confirm={gettext("Delete this item?")}
                class="font-medium text-rose-600 opacity-80 hover:opacity-100"
              >
                {gettext("delete")}
              </button>
            </div>
          </div>
        </div>
      </div>

      <p
        :if={@item_count == 0}
        class="rounded-lg border border-dashed border-slate-300 bg-white px-5 py-10 text-center text-sm text-slate-500"
      >
        {gettext("No media yet — upload something above.")}
      </p>
    </div>
    """
  end

  defp status_class("ready"),
    do: "rounded-full bg-emerald-50 px-2 py-0.5 font-medium text-emerald-700"

  defp status_class("failed"), do: "rounded-full bg-rose-50 px-2 py-0.5 font-medium text-rose-700"
  defp status_class(_), do: "rounded-full bg-slate-100 px-2 py-0.5 font-medium text-slate-600"

  defp error_to_string(:too_large), do: gettext("Too large")
  defp error_to_string(:not_accepted), do: gettext("Unsupported file type")
  defp error_to_string(:too_many_files), do: gettext("Too many files")
  defp error_to_string(other), do: inspect(other)
end
