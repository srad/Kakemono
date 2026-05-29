defmodule KakemonoWeb.ControlLive.Backups do
  use KakemonoWeb, :live_view

  alias Kakemono.Backup

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Backups")
     |> assign(:active_nav, :backups)
     |> assign(:backups, Backup.list())
     |> assign(:creating, false)}
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
    <div class="max-w-5xl space-y-6">
      <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p class="text-sm font-medium text-slate-500">Administration</p>
          <h1 class="text-2xl font-semibold tracking-tight text-slate-950">Backups</h1>
        </div>
        <p class="text-sm text-slate-500">{length(@backups)} backup files</p>
      </div>

      <div class="flex flex-col gap-3 rounded-lg border border-slate-200 bg-white p-5 shadow-sm sm:flex-row sm:items-center">
        <button
          phx-click="create"
          disabled={@creating}
          class="inline-flex h-10 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {if @creating, do: "Creating…", else: "Create backup"}
        </button>
        <span class="text-sm text-slate-500">
          Archives the database and uploads into a zip file.
        </span>
      </div>

      <p
        :if={@backups == [] and not @creating}
        class="rounded-lg border border-dashed border-slate-300 bg-white px-5 py-10 text-center text-sm text-slate-500"
      >
        No backups yet — click Create backup above.
      </p>

      <table
        :if={@backups != []}
        class="w-full overflow-hidden rounded-lg border border-slate-200 bg-white text-sm shadow-sm"
      >
        <thead class="bg-slate-50 text-left text-slate-600">
          <tr>
            <th class="px-3 py-2 font-medium">Filename</th>
            <th class="px-3 py-2 font-medium">Size</th>
            <th class="px-3 py-2 font-medium">Created</th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr :for={b <- @backups} class="border-t border-slate-200 hover:bg-slate-50">
            <td class="px-3 py-2 font-mono text-xs text-slate-800">{b.filename}</td>
            <td class="px-3 py-2 tabular-nums text-slate-700">{format_size(b.size)}</td>
            <td class="px-3 py-2 tabular-nums text-slate-700">{format_datetime(b.created_at)}</td>
            <td class="px-3 py-2">
              <div class="flex gap-3 justify-end">
                <a
                  href={~p"/c/backups/#{b.filename}/download"}
                  download={b.filename}
                  class="font-medium text-slate-700 hover:text-slate-950"
                >
                  Download
                </a>
                <button
                  phx-click="delete"
                  phx-value-filename={b.filename}
                  data-confirm={"Delete #{b.filename}?"}
                  class="font-medium text-rose-600 hover:text-rose-700"
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <p class="text-xs text-slate-500">
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
