defmodule KakemonoWeb.PlaylistsLive.Index do
  use KakemonoWeb, :live_view
  alias Kakemono.Playlists

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Playlists") |> assign(:playlists, Playlists.list())}
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
    <div class="p-6 w-full">
      <h1 class="text-2xl font-bold mb-4">Playlists</h1>

      <form phx-submit="create" class="mb-6 flex gap-2">
        <input name="name" placeholder="New playlist name" class="flex-1 border rounded px-3 py-2" />
        <button class="bg-primary text-primary-foreground px-4 py-2 rounded">Create</button>
      </form>

      <ul class="divide-y border rounded">
        <li :for={p <- @playlists} class="flex justify-between items-center p-3">
          <.link navigate={~p"/c/playlists/#{p.id}"} class="text-blue-600 hover:underline">
            {p.name}
          </.link>
          <button
            phx-click="delete"
            phx-value-id={p.id}
            data-confirm="Delete playlist?"
            class="text-red-600 text-sm"
          >
            delete
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
