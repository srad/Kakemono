defmodule Kakemono.Media.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "media_items" do
    field :filename, :string
    field :original_filename, :string
    field :mime_type, :string
    field :width, :integer
    field :height, :integer
    field :duration_ms, :integer
    field :thumbnail_path, :string
    field :status, :string, default: "pending"
    timestamps()
  end

  def changeset(i, attrs) do
    i
    |> cast(attrs, [
      :filename,
      :original_filename,
      :mime_type,
      :width,
      :height,
      :duration_ms,
      :thumbnail_path,
      :status
    ])
    |> validate_required([:filename, :original_filename, :mime_type, :status])
    |> validate_inclusion(:status, ["pending", "ready", "failed"])
  end

  @doc "Returns :image | :video based on mime_type"
  def kind(%__MODULE__{mime_type: mt}), do: kind_from_mime(mt)
  def kind_from_mime("image/" <> _), do: :image
  def kind_from_mime("video/" <> _), do: :video
  def kind_from_mime(_), do: :unknown
end
