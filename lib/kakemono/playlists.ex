defmodule Kakemono.Playlists do
  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Playlists.{Playlist, Entry}
  alias Kakemono.Displays

  @pubsub Kakemono.PubSub

  def list, do: Repo.all(from p in Playlist, order_by: [asc: p.name])

  def get!(id), do: Repo.get!(Playlist, id)
  def get(id), do: Repo.get(Playlist, id)

  def get_with_items(id) do
    case Repo.get(Playlist, id) do
      nil ->
        nil

      p ->
        entries =
          from(e in Entry,
            where: e.playlist_id == ^id,
            order_by: [asc: e.order_index],
            preload: [:media_item]
          )
          |> Repo.all()

        %{p | entries: entries}
    end
  end

  def create(attrs) do
    %Playlist{} |> Playlist.changeset(attrs) |> Repo.insert()
  end

  def delete(%Playlist{} = p), do: Repo.delete(p)

  def add_item(%Playlist{id: pid}, media_item_id) do
    next =
      (Repo.one(from e in Entry, where: e.playlist_id == ^pid, select: max(e.order_index)) || -1) +
        1

    %Entry{}
    |> Entry.changeset(%{playlist_id: pid, media_item_id: media_item_id, order_index: next})
    |> Repo.insert()
    |> tap(fn _ -> broadcast_updated(pid) end)
  end

  def remove_entry(entry_id) do
    case Repo.get(Entry, entry_id) do
      nil ->
        :ok

      e ->
        pid = e.playlist_id
        {:ok, _} = Repo.delete(e)
        # compact order_index
        from(x in Entry, where: x.playlist_id == ^pid, order_by: [asc: x.order_index])
        |> Repo.all()
        |> Enum.with_index()
        |> Enum.each(fn {x, idx} ->
          Ecto.Changeset.change(x, order_index: idx) |> Repo.update!()
        end)

        broadcast_updated(pid)
        :ok
    end
  end

  @doc """
  Reorder entries. `entry_ids` is the full list of entry ids in their new order.
  Two-pass: temp offset to avoid unique-index collision on (playlist_id, order_index).
  """
  def reorder(playlist_id, entry_ids) when is_list(entry_ids) do
    Repo.transaction(fn ->
      # First pass: shift all entries into safe range
      offset = 100_000

      Enum.with_index(entry_ids, fn id, idx ->
        from(e in Entry, where: e.id == ^id and e.playlist_id == ^playlist_id)
        |> Repo.update_all(set: [order_index: offset + idx])
      end)

      # Second pass: assign final 0..n-1
      Enum.with_index(entry_ids, fn id, idx ->
        from(e in Entry, where: e.id == ^id and e.playlist_id == ^playlist_id)
        |> Repo.update_all(set: [order_index: idx])
      end)
    end)

    broadcast_updated(playlist_id)
    :ok
  end

  @doc "Update the playlist's display settings (name, fit_mode). Broadcasts to displays."
  def update_settings(%Playlist{} = pl, attrs) do
    with {:ok, updated} <- pl |> Playlist.changeset(attrs) |> Repo.update() do
      broadcast_updated(updated.id)
      {:ok, updated}
    end
  end

  defp broadcast_updated(playlist_id) do
    # In Phase 1, broadcast to all known displays. Phase 3+ will introduce a
    # display↔playlist mapping; for now any display showing this playlist reacts.
    for d <- Displays.list() do
      Phoenix.PubSub.broadcast(
        @pubsub,
        "display:#{d.id}",
        {:playlist_updated, %{playlist_id: playlist_id}}
      )
    end

    :ok
  end
end
