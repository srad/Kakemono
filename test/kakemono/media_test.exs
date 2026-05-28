defmodule Kakemono.MediaTest do
  use Kakemono.DataCase, async: false
  use Oban.Testing, repo: Kakemono.Repo, engine: Oban.Engines.Lite, notifier: Oban.Notifiers.PG

  alias Kakemono.Media
  alias Kakemono.Media.{Item, TranscodeWorker}
  import Kakemono.Fixtures

  setup do
    on_exit(fn ->
      File.rm_rf!(Media.uploads_dir())
    end)

    :ok
  end

  test "upload/2 copies the file to uploads dir, creates a pending item, enqueues TranscodeWorker" do
    src = write_test_jpeg()
    {:ok, item} = Media.upload(src, %{original_filename: "test.jpg", mime_type: "image/jpeg"})

    assert item.status == "pending"
    assert item.original_filename == "test.jpg"
    assert String.ends_with?(item.filename, ".jpg")
    assert File.exists?(Path.join(Media.uploads_dir(), item.filename))

    assert_enqueued(worker: TranscodeWorker, args: %{"id" => item.id})
  end

  test "list_items/0 returns items in descending insertion order" do
    a = media_item_fixture(original_filename: "a.jpg")
    Process.sleep(10)
    b = media_item_fixture(original_filename: "b.jpg")
    assert [first, second] = Media.list_items()
    assert first.id == b.id
    assert second.id == a.id
  end

  test "delete_item/1 removes the row and best-effort the file" do
    src = write_test_jpeg()
    {:ok, item} = Media.upload(src, %{original_filename: "x.jpg", mime_type: "image/jpeg"})
    {:ok, _} = Media.delete_item(item)
    refute Media.get_item(item.id)
    refute File.exists?(Path.join(Media.uploads_dir(), item.filename))
  end

  test "Item.kind/1 maps mime_type to :image | :video | :unknown" do
    assert Item.kind(%Item{mime_type: "image/jpeg"}) == :image
    assert Item.kind(%Item{mime_type: "video/mp4"}) == :video
    assert Item.kind(%Item{mime_type: "application/octet-stream"}) == :unknown
  end

  test "TranscodeWorker.perform/1 sets status=ready, generates a thumbnail for an image" do
    src = write_test_jpeg()
    {:ok, item} = Media.upload(src, %{original_filename: "img.jpg", mime_type: "image/jpeg"})

    assert :ok = perform_job(TranscodeWorker, %{"id" => item.id})

    reloaded = Media.get_item!(item.id)
    assert reloaded.status == "ready"
    assert reloaded.thumbnail_path
    assert File.exists?(Path.join(Media.uploads_dir(), reloaded.thumbnail_path))
  end

  test "TranscodeWorker.perform/1 with a missing item is a no-op" do
    assert :ok = perform_job(TranscodeWorker, %{"id" => 999_999})
  end

  test "TranscodeWorker.perform/1 marks failed for a non-image, non-video stub when source unreadable" do
    item = media_item_fixture(filename: "missing.jpg", status: "pending")
    # No file on disk; image transcode path will rescue and mark failed
    assert :ok = perform_job(TranscodeWorker, %{"id" => item.id})
    assert Media.get_item!(item.id).status == "failed"
  end
end
