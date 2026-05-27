defmodule Kakemono.Playlists.Playlist do
  use Ecto.Schema
  import Ecto.Changeset

  @fit_modes ~w(contain cover fill scale-down none)

  schema "playlists" do
    field :name, :string
    field :fit_mode, :string, default: "contain"
    field :transition_duration_ms, :integer
    has_many :entries, Kakemono.Playlists.Entry, preload_order: [asc: :order_index]
    timestamps()
  end

  def fit_modes, do: @fit_modes

  def changeset(p, attrs) do
    p
    |> cast(attrs, [:name, :fit_mode, :transition_duration_ms])
    |> validate_required([:name, :fit_mode])
    |> validate_inclusion(:fit_mode, @fit_modes)
    |> validate_number(:transition_duration_ms,
      greater_than_or_equal_to: 500,
      less_than_or_equal_to: 600_000
    )
  end
end
