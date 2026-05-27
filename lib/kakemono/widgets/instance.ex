defmodule Kakemono.Widgets.Instance do
  use Ecto.Schema
  import Ecto.Changeset

  schema "widget_instances" do
    field :widget_type, :string
    field :config, :map, default: %{}
    belongs_to :scene, Kakemono.Scenes.Scene
    timestamps()
  end

  def changeset(i, attrs) do
    i
    |> cast(attrs, [:widget_type, :config, :scene_id])
    |> validate_required([:widget_type, :config, :scene_id])
    |> foreign_key_constraint(:scene_id)
  end
end
