defmodule KakemonoWeb.ControlLive.Backups do
  use KakemonoWeb, :live_view

  alias Kakemono.Backup

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:backups, Backup.list()) |> assign(:creating, false)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    send(self(), :do_create)
    {:noreply, assign(socket, :creating, true)}
  end

  def handle_event("delete", %{"filename" => filename}, socket) do
    case Backup.delete(filename) do
      :ok ->
        {:noreply,
         socket |> assign(:backups, Backup.list()) |> put_flash(:info, "Backup deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete backup")}
    end
  end

  @impl true
  def handle_info(:do_create, socket) do
    case Backup.create() do
      {:ok, _filename} ->
        {:noreply,
         socket
         |> assign(:creating, false)
         |> assign(:backups, Backup.list())
         |> put_flash(:info, "Backup created")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:creating, false)
         |> put_flash(:error, "Backup failed: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6 w-full max-w-3xl">
      <h1 class="text-2xl font-bold">Backups</h1>
      <nav class="flex gap-4 text-blue-600">
        <.link navigate={~p"/c"}>← Control panel</.link>
      </nav>

      <div class="flex items-center gap-3">
        <button
          phx-click="create"
          disabled={@creating}
          class="bg-primary text-primary-foreground px-4 py-2 rounded disabled:opacity-50"
        >
          {if @creating, do: "Creating…", else: "Create backup"}
        </button>
        <span class="text-sm text-gray-500">
          Archives the database and uploads into a zip file.
        </span>
      </div>

      <p :if={@backups == [] and not @creating} class="text-gray-500 text-sm">
        No backups yet — click Create backup above.
      </p>

      <table :if={@backups != []} class="w-full text-sm border rounded overflow-hidden">
        <thead class="bg-gray-50 text-left">
          <tr>
            <th class="px-3 py-2 font-medium">Filename</th>
            <th class="px-3 py-2 font-medium">Size</th>
            <th class="px-3 py-2 font-medium">Created</th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr :for={b <- @backups} class="border-t hover:bg-gray-50">
            <td class="px-3 py-2 font-mono text-xs">{b.filename}</td>
            <td class="px-3 py-2 tabular-nums">{format_size(b.size)}</td>
            <td class="px-3 py-2 tabular-nums">{format_datetime(b.created_at)}</td>
            <td class="px-3 py-2">
              <div class="flex gap-3 justify-end">
                <a
                  href={~p"/c/backups/#{b.filename}/download"}
                  download={b.filename}
                  class="text-blue-600 hover:underline"
                >
                  Download
                </a>
                <button
                  phx-click="delete"
                  phx-value-filename={b.filename}
                  data-confirm={"Delete #{b.filename}?"}
                  class="text-red-600 hover:underline"
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <p class="text-xs text-gray-400">
        Stored in <code class="font-mono">{Backup.backups_dir()}</code>
      </p>
    </div>
    """
  end

  defp format_size(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{div(bytes, 1_024)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end
end
