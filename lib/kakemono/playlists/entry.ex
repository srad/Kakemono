defmodule Kakemono.Playlists.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "playlist_entries" do
    field :order_index, :integer
    belongs_to :playlist, Kakemono.Playlists.Playlist
    belongs_to :media_item, Kakemono.Media.Item
    timestamps()
  end

  def changeset(e, attrs) do
    e
    |> cast(attrs, [:order_index, :playlist_id, :media_item_id])
    |> validate_required([:order_index, :playlist_id, :media_item_id])
  end
end
