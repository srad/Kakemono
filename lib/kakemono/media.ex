defmodule Kakemono.Media do
  @moduledoc """
  Media context. Owns Media.Item rows and the on-disk uploads directory.
  """
  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Media.Item
  alias Kakemono.Media.TranscodeWorker

  def uploads_dir do
    dir = Kakemono.DataDir.uploads_dir()

    File.mkdir_p!(dir)
    dir
  end

  def thumb_dir do
    dir = Path.join(uploads_dir(), "thumbs")
    File.mkdir_p!(dir)
    dir
  end

  def list_items(_opts \\ []) do
    Repo.all(from i in Item, order_by: [desc: i.inserted_at, desc: i.id])
  end

  def get_item!(id), do: Repo.get!(Item, id)
  def get_item(id), do: Repo.get(Item, id)

  @doc """
  Persists an uploaded file. `path` is a tmp path on disk; `meta` carries
  `:original_filename` and `:mime_type`. Returns {:ok, item} after enqueueing
  the TranscodeWorker job.
  """
  def upload(path, meta) do
    ext = Path.extname(meta[:original_filename] || meta["original_filename"] || "")
    uuid = Ecto.UUID.generate()
    dest_name = uuid <> String.downcase(ext)
    dest_path = Path.join(uploads_dir(), dest_name)
    File.cp!(path, dest_path)

    attrs = %{
      filename: dest_name,
      original_filename: meta[:original_filename] || meta["original_filename"],
      mime_type: meta[:mime_type] || meta["mime_type"] || "application/octet-stream",
      status: "pending"
    }

    with {:ok, item} <- %Item{} |> Item.changeset(attrs) |> Repo.insert(),
         {:ok, _job} <- %{id: item.id} |> TranscodeWorker.new() |> Oban.insert() do
      Phoenix.PubSub.broadcast(Kakemono.PubSub, "media", {:media_created, item})
      {:ok, item}
    end
  end

  def delete_item(%Item{} = item) do
    _ = File.rm(Path.join(uploads_dir(), item.filename))
    if item.thumbnail_path, do: _ = File.rm(Path.join(uploads_dir(), item.thumbnail_path))
    Repo.delete(item)
  end

  def update(%Item{} = item, attrs) do
    with {:ok, updated} <- item |> Item.changeset(attrs) |> Repo.update() do
      Phoenix.PubSub.broadcast(Kakemono.PubSub, "media", {:media_updated, updated})
      {:ok, updated}
    end
  end

  def absolute_path(%Item{} = item), do: Path.join(uploads_dir(), item.filename)

  @doc "Public web URL for the media file."
  def url(%Item{filename: f}), do: "/uploads/" <> f
  def thumb_url(%Item{thumbnail_path: nil}), do: nil
  def thumb_url(%Item{thumbnail_path: t}), do: "/uploads/" <> t
end
