defmodule KakemonoWeb.PlaylistsLiveTest do
  use KakemonoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Kakemono.Fixtures

  alias Kakemono.Playlists

  test "index lists existing playlists and can create a new one", %{conn: conn} do
    playlist_fixture(name: "Alpha")
    {:ok, view, html} = live(conn, "/c/playlists")
    assert html =~ "Alpha"

    view |> form("form", %{name: "Beta"}) |> render_submit()
    assert render(view) =~ "Beta"
  end

  test "edit page renders entries and add buttons for ready media", %{conn: conn} do
    p = playlist_fixture()
    i = media_item_fixture(status: "ready", original_filename: "candidate.jpg")
    {:ok, _} = Playlists.add_item(p, i.id)

    {:ok, _view, html} = live(conn, "/c/playlists/#{p.id}")
    assert html =~ "candidate.jpg"
    assert html =~ "Or add existing media"
  end

  test "edit page renders inline upload form", %{conn: conn} do
    pl = Kakemono.Fixtures.playlist_fixture()
    {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, ~p"/c/playlists/#{pl.id}")
    assert html =~ "Upload &amp; auto-add to this playlist"
    assert html =~ ~s(id="playlist-upload")
  end

  test "playlist index renders full-width container", %{conn: conn} do
    {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, ~p"/c/playlists")
    refute html =~ "max-w-3xl"
  end

  test "media index renders full-width container", %{conn: conn} do
    {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, ~p"/c/media")
    refute html =~ "max-w-5xl"
  end

  test "edit upload form has submit-based progress UI", %{conn: conn} do
    pl = Kakemono.Fixtures.playlist_fixture()
    {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, ~p"/c/playlists/#{pl.id}")
    assert html =~ ~s(id="playlist-upload")
    assert html =~ "Upload"
  end

  test "single-file upload through playlist edit form adds the entry", %{conn: conn} do
    pl = Kakemono.Fixtures.playlist_fixture()
    {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, ~p"/c/playlists/#{pl.id}")

    jpeg = File.read!(Kakemono.Fixtures.write_test_jpeg())
    name = "pl-single-#{System.unique_integer([:positive])}.jpg"

    input =
      Phoenix.LiveViewTest.file_input(view, "#playlist-upload", :files, [
        %{name: name, content: jpeg, type: "image/jpeg", size: byte_size(jpeg)}
      ])

    Phoenix.LiveViewTest.render_upload(input, name)

    view
    |> Phoenix.LiveViewTest.element("#playlist-upload")
    |> Phoenix.LiveViewTest.render_submit()

    reloaded = Kakemono.Playlists.get_with_items(pl.id)
    uploaded_names = Enum.map(reloaded.entries, & &1.media_item.original_filename)
    assert name in uploaded_names
  end

  # Production regression: uploading multiple files into a playlist only added
  # one entry. Guard the backend behaviour the save handler relies on.
  test "uploading N media via the backend and adding each to a playlist preserves order" do
    pl = Kakemono.Fixtures.playlist_fixture()
    src = Kakemono.Fixtures.write_test_jpeg()

    items =
      for i <- 1..5 do
        {:ok, item} =
          Kakemono.Media.upload(src, %{
            original_filename: "batch-pl-#{i}-#{System.unique_integer([:positive])}.jpg",
            mime_type: "image/jpeg"
          })

        {:ok, _entry} = Kakemono.Playlists.add_item(pl, item.id)
        item
      end

    reloaded = Kakemono.Playlists.get_with_items(pl.id)
    assert length(reloaded.entries) == 5
    expected = Enum.map(items, & &1.original_filename)
    actual = Enum.map(reloaded.entries, & &1.media_item.original_filename)
    assert expected == actual
  end

  describe "playlist settings form" do
    test "update_settings sets transition_duration_ms", %{conn: conn} do
      pl = Kakemono.Fixtures.playlist_fixture()
      {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, ~p"/c/playlists/#{pl.id}")

      view
      |> Phoenix.LiveViewTest.form("form[phx-change='update_settings']", %{
        "fit_mode" => "contain",
        "transition_duration_ms" => "12000"
      })
      |> Phoenix.LiveViewTest.render_change()

      updated = Kakemono.Playlists.get!(pl.id)
      assert updated.transition_duration_ms == 12_000
    end

    test "update_settings clears transition_duration_ms when blank", %{conn: conn} do
      pl = Kakemono.Fixtures.playlist_fixture()
      {:ok, _} = Kakemono.Playlists.update_settings(pl, %{transition_duration_ms: 9000})
      {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, ~p"/c/playlists/#{pl.id}")

      view
      |> Phoenix.LiveViewTest.form("form[phx-change='update_settings']", %{
        "fit_mode" => "contain",
        "transition_duration_ms" => ""
      })
      |> Phoenix.LiveViewTest.render_change()

      assert Kakemono.Playlists.get!(pl.id).transition_duration_ms == nil
    end

    test "update_settings rejects out-of-range value", %{conn: conn} do
      pl = Kakemono.Fixtures.playlist_fixture()
      {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, ~p"/c/playlists/#{pl.id}")

      html =
        view
        |> Phoenix.LiveViewTest.form("form[phx-change='update_settings']", %{
          "fit_mode" => "contain",
          "transition_duration_ms" => "100"
        })
        |> Phoenix.LiveViewTest.render_change()

      assert html =~ "Invalid settings"
      assert Kakemono.Playlists.get!(pl.id).transition_duration_ms == nil
    end
  end
end
