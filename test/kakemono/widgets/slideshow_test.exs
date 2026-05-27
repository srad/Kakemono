defmodule Kakemono.Widgets.SlideshowTest do
  use Kakemono.DataCase, async: false

  alias Kakemono.Widgets
  alias Kakemono.Widgets.Slideshow
  import Kakemono.Fixtures

  setup do
    %{scene: scene_fixture()}
  end

  test "registry exposes the slideshow type" do
    assert "slideshow" in Kakemono.Widgets.Registry.types()
    assert Kakemono.Widgets.Registry.fetch("slideshow") == Slideshow
  end

  test "create_instance validates playlist_id is required", %{scene: scene} do
    assert {:error, {:invalid_config, _}} = Widgets.create_instance("slideshow", scene.id, %{})
  end

  test "create_instance accepts a playlist_id and stores it", %{scene: scene} do
    pl = playlist_fixture()
    assert {:ok, inst} = Widgets.create_instance("slideshow", scene.id, %{"playlist_id" => pl.id})
    assert inst.config["playlist_id"] == pl.id
  end

  test "items_for resolves entries with playlist override", %{scene: scene} do
    pl = playlist_fixture()
    {:ok, _} = Kakemono.Playlists.update_settings(pl, %{transition_duration_ms: 9_000})
    img = media_item_fixture(%{mime_type: "image/jpeg", duration_ms: nil})
    {:ok, _} = Kakemono.Playlists.add_item(pl, img.id)
    {:ok, inst} = Widgets.create_instance("slideshow", scene.id, %{"playlist_id" => pl.id})

    {pl2, [item]} = Slideshow.items_for(inst)
    assert pl2.id == pl.id
    assert item.duration_ms == 9_000
    assert item.type == "image"
  end

  test "items_for returns empty when playlist is missing", %{scene: scene} do
    {:ok, inst} = Widgets.create_instance("slideshow", scene.id, %{"playlist_id" => 999_999})
    assert {nil, []} = Slideshow.items_for(inst)
  end
end
