defmodule KakemonoWeb.PlaylistsLive.Index do
  use KakemonoWeb, :live_view
  alias Kakemono.Playlists

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Playlists"))
     |> assign(:active_nav, :playlists)
     |> assign(:playlists, Playlists.list())}
  end

  @impl true
  def handle_event("create", %{"name" => name}, socket) when name != "" do
    {:ok, _} = Playlists.create(%{name: name})
    {:noreply, assign(socket, :playlists, Playlists.list())}
  end

  def handle_event("create", _, socket), do: {:noreply, socket}

  def handle_event("delete", %{"id" => id}, socket) do
    p = Playlists.get!(id)
    {:ok, _} = Playlists.delete(p)
    {:noreply, assign(socket, :playlists, Playlists.list())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p class="text-sm font-medium text-slate-500">{gettext("Playback")}</p>
          <h1 class="text-2xl font-semibold tracking-tight text-slate-950">{gettext("Playlists")}</h1>
        </div>
        <p class="text-sm text-slate-500">{ngettext("1 playlist", "%{count} playlists", length(@playlists))}</p>
      </div>

      <form
        phx-submit="create"
        class="flex flex-col gap-3 rounded-lg border border-slate-200 bg-white p-5 shadow-sm sm:flex-row"
      >
        <input
          name="name"
          placeholder={gettext("New playlist name")}
          class="flex-1 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
        />
        <button class="inline-flex h-10 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800">
          {gettext("Create")}
        </button>
      </form>

      <ul class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
        <li
          :for={p <- @playlists}
          class="flex items-center justify-between gap-3 border-b border-slate-200 px-5 py-4 last:border-b-0"
        >
          <div class="min-w-0">
            <.link
              navigate={~p"/c/playlists/#{p.id}"}
              class="truncate font-medium text-slate-950 hover:text-slate-700"
            >
              {p.name}
            </.link>
            <p class="text-sm text-slate-500">Playlist #{p.id}</p>
          </div>
          <button
            phx-click="delete"
            phx-value-id={p.id}
            data-confirm={gettext("Delete playlist?")}
            class="rounded-md px-2.5 py-1.5 text-sm font-medium text-rose-600 transition hover:bg-rose-50"
          >
            {gettext("delete")}
          </button>
        </li>
      </ul>

      <p
        :if={@playlists == []}
        class="rounded-lg border border-dashed border-slate-300 bg-white px-5 py-10 text-center text-sm text-slate-500"
      >
        {gettext("No playlists yet. Create one above.")}
      </p>
    </div>
    """
  end
end
