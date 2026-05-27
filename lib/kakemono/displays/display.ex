defmodule Kakemono.Displays.Display do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "displays" do
    field :name, :string
    field :current_scene_id, :integer
    field :last_heartbeat_at, :utc_datetime
    timestamps()
  end

  def changeset(d, attrs) do
    d
    |> cast(attrs, [:id, :name, :current_scene_id, :last_heartbeat_at])
    |> validate_required([:id, :name])
  end
end
