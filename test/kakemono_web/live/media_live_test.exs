defmodule KakemonoWeb.MediaLiveTest do
  use KakemonoWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "single-file upload through the LiveView form" do
    test "uploads one file and it appears in the library", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/media")

      jpeg = File.read!(Kakemono.Fixtures.write_test_jpeg())
      name = "lv-single-#{System.unique_integer([:positive])}.jpg"

      input =
        file_input(view, "#upload-form", :files, [
          %{name: name, content: jpeg, type: "image/jpeg", size: byte_size(jpeg)}
        ])

      render_upload(input, name)
      view |> element("#upload-form") |> render_submit()

      names = Kakemono.Media.list_items() |> Enum.map(& &1.original_filename)
      assert name in names
    end
  end

  describe "Media.upload backend handles multi-file batches" do
    # Production regression: when multiple files were uploaded, only one made
    # it into the library. Guard the backend code path that the save handler
    # calls once per entry in the same batch.
    test "three concurrent Media.upload calls all succeed with distinct destinations" do
      src = Kakemono.Fixtures.write_test_jpeg()

      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            Kakemono.Media.upload(src, %{
              original_filename: "batch-#{i}-#{System.unique_integer([:positive])}.jpg",
              mime_type: "image/jpeg"
            })
          end)
        end

      results = Task.await_many(tasks, 5_000)

      assert Enum.all?(results, &match?({:ok, _}, &1)),
             "expected all uploads to succeed, got: #{inspect(results)}"

      items = Enum.map(results, fn {:ok, it} -> it end)
      filenames = Enum.map(items, & &1.filename)
      assert length(Enum.uniq(filenames)) == 3, "destination filenames must be unique"

      for item <- items do
        path = Path.join(Kakemono.Media.uploads_dir(), item.filename)
        assert File.exists?(path), "uploaded file missing on disk: #{path}"
      end
    end

    test "20 sequential Media.upload calls all succeed" do
      src = Kakemono.Fixtures.write_test_jpeg()

      results =
        for i <- 1..20 do
          Kakemono.Media.upload(src, %{
            original_filename: "seq-#{i}-#{System.unique_integer([:positive])}.jpg",
            mime_type: "image/jpeg"
          })
        end

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
