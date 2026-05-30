defmodule KakemonoWeb.DisplayLiveTest do
  use KakemonoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Kakemono.Fixtures

  alias Kakemono.{Displays, Playlists, Scenes, Widgets}

  setup do
    display_fixture(id: "tablet")
    :ok
  end

  defp slideshow_scene!(display_id, playlist_id, opts \\ %{}) do
    cfg = Map.merge(%{"playlist_id" => playlist_id}, opts)

    {:ok, scene} =
      Scenes.create(%{
        name: "S#{System.unique_integer([:positive])}",
        mode: "fullscreen_widget",
        layout: %{"widget_instance_id" => 0}
      })

    {:ok, inst} = Widgets.create_instance("slideshow", scene.id, cfg)

    {:ok, scene} =
      Scenes.update(scene, %{layout: %{"widget_instance_id" => inst.id}})

    {:ok, _} = Displays.set_scene(display_id, scene.id)
    {scene, inst}
  end

  defp weather_scene!(display_id, opts \\ %{}) do
    cfg =
      Map.merge(
        %{
          "label" => "Berlin",
          "latitude" => 52.52,
          "longitude" => 13.405,
          "timezone" => "Europe/Berlin",
          "cached" => %{
            "utc_offset_seconds" => 7200,
            "current" => %{"temperature_2m" => 21.0, "weather_code" => 0, "is_day" => 1}
          }
        },
        opts
      )

    {:ok, scene} =
      Scenes.create(%{
        name: "W#{System.unique_integer([:positive])}",
        mode: "fullscreen_widget",
        layout: %{"widget_instance_id" => 0}
      })

    {:ok, inst} = Widgets.create_instance("weather", scene.id, cfg)
    {:ok, scene} = Scenes.update(scene, %{layout: %{"widget_instance_id" => inst.id}})
    {:ok, _} = Displays.set_scene(display_id, scene.id)
    {scene, inst}
  end

  test "auto-registers an unknown display id and renders the empty panel", %{conn: conn} do
    id = "auto-#{System.unique_integer([:positive])}"
    refute Displays.get(id)
    {:ok, _view, html} = live(conn, "/d/#{id}")
    assert Displays.get(id), "display should have been auto-registered"
    assert html =~ "Kakemono Display"
    assert html =~ id
    assert html =~ "No scene assigned"
  end

  test "with no scene shows the onboarding empty panel (not a slideshow)", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/d/tablet")
    assert html =~ "No scene assigned"
    refute html =~ ~s(phx-hook="Slideshow")
  end

  test "renders the Slideshow widget hook with empty items when playlist is empty", %{conn: conn} do
    pl = playlist_fixture()
    slideshow_scene!("tablet", pl.id)

    {:ok, _view, html} = live(conn, "/d/tablet")
    assert html =~ ~s(phx-hook="Slideshow")
    assert html =~ "data-items=\"[]\""
  end

  test "renders items JSON when the Slideshow's playlist has entries", %{conn: conn} do
    pl = playlist_fixture()
    m = media_item_fixture()
    {:ok, _} = Playlists.add_item(pl, m.id)
    slideshow_scene!("tablet", pl.id)

    {:ok, _view, html} = live(conn, "/d/tablet")
    assert html =~ ~s(phx-hook="Slideshow")
    assert html =~ "/uploads/"
    assert html =~ "&quot;type&quot;:&quot;image&quot;"
  end

  test "playlist reorder pushes a scoped slideshow:update event", %{conn: conn} do
    pl = playlist_fixture()
    i1 = media_item_fixture()
    i2 = media_item_fixture()
    {:ok, e1} = Playlists.add_item(pl, i1.id)
    {:ok, e2} = Playlists.add_item(pl, i2.id)
    {_scene, inst} = slideshow_scene!("tablet", pl.id)

    {:ok, view, _html} = live(conn, "/d/tablet")

    :ok = Playlists.reorder(pl.id, [e2.id, e1.id])

    iid = inst.id
    assert_push_event(view, "slideshow:update", %{instance_id: ^iid, items: [first, second]})
    assert first.id == i2.id
    assert second.id == i1.id
  end

  test "reloadPage command pushes fully_kiosk event", %{conn: conn} do
    d = display!("reload-#{System.unique_integer([:positive])}")
    {:ok, view, _html} = live(conn, ~p"/d/#{d.id}")

    Phoenix.PubSub.broadcast(Kakemono.PubSub, "display:#{d.id}", {:fully_kiosk_cmd, "reloadPage"})

    assert_push_event(view, "fully_kiosk", %{cmd: "reloadPage"})
  end

  test "renders data-fit-mode from the playlist default", %{conn: conn} do
    d = display!("dfit-#{System.unique_integer([:positive])}")
    pl = playlist_fixture()
    m = media_item_fixture()
    {:ok, _} = Playlists.add_item(pl, m.id)
    {:ok, _} = Playlists.update_settings(pl, %{fit_mode: "cover"})
    slideshow_scene!(d.id, pl.id)

    {:ok, _view, html} = live(conn, ~p"/d/#{d.id}")
    assert html =~ ~s(data-fit-mode="cover")
  end

  test "widget config fit_mode wins over playlist default", %{conn: conn} do
    d = display!("dfit2-#{System.unique_integer([:positive])}")
    pl = playlist_fixture()
    m = media_item_fixture()
    {:ok, _} = Playlists.add_item(pl, m.id)
    {:ok, _} = Playlists.update_settings(pl, %{fit_mode: "cover"})
    slideshow_scene!(d.id, pl.id, %{"fit_mode" => "contain"})

    {:ok, _view, html} = live(conn, ~p"/d/#{d.id}")
    assert html =~ ~s(data-fit-mode="contain")
  end

  test "HTTP response uses display layout only (no app-layout wrapper)", %{conn: conn} do
    conn = get(conn, "/d/tablet")
    body = html_response(conn, 200)

    refute body =~ "bg-gray-50",
           "display route is wrapped in app layout; expected layout: false in router"
  end

  test "preview route can force a weather state for visual inspection", %{conn: conn} do
    d = display!("weather-preview-#{System.unique_integer([:positive])}")
    {scene, _inst} = weather_scene!(d.id)

    {:ok, _view, html} =
      live(conn, ~p"/d/preview?scene=#{scene.name}&weather_cond=cloudy&weather_tod=day")

    assert html =~ ~s(class="kakemono-widget kakemono-widget-weather")
    assert html =~ ~s(data-cond="cloudy")
    assert html =~ ~s(data-preview-tod="day")
    assert html =~ "Overcast"
  end

  test "playlist transition_duration_ms override applies to all items", %{conn: conn} do
    d = display!("dtd-#{System.unique_integer([:positive])}")
    pl = playlist_fixture()
    img = media_item_fixture(%{mime_type: "image/jpeg", duration_ms: nil})

    vid =
      media_item_fixture(%{
        filename: "v.mp4",
        original_filename: "v.mp4",
        mime_type: "video/mp4",
        duration_ms: 30_000
      })

    {:ok, _} = Playlists.add_item(pl, img.id)
    {:ok, _} = Playlists.add_item(pl, vid.id)
    {:ok, _} = Playlists.update_settings(pl, %{transition_duration_ms: 15_000})
    slideshow_scene!(d.id, pl.id)

    {:ok, _view, html} = live(conn, ~p"/d/#{d.id}")
    assert html =~ ~s(duration_ms&quot;:15000)
    refute html =~ ~s(duration_ms&quot;:30000)
    refute html =~ ~s(duration_ms&quot;:6000)
  end

  test "without override, image falls back to 6000 and video keeps natural duration", %{
    conn: conn
  } do
    d = display!("dtd2-#{System.unique_integer([:positive])}")
    pl = playlist_fixture()
    img = media_item_fixture(%{mime_type: "image/jpeg", duration_ms: nil})

    vid =
      media_item_fixture(%{
        filename: "v2.mp4",
        original_filename: "v2.mp4",
        mime_type: "video/mp4",
        duration_ms: 30_000
      })

    {:ok, _} = Playlists.add_item(pl, img.id)
    {:ok, _} = Playlists.add_item(pl, vid.id)
    slideshow_scene!(d.id, pl.id)

    {:ok, _view, html} = live(conn, ~p"/d/#{d.id}")
    assert html =~ ~s(duration_ms&quot;:6000)
    assert html =~ ~s(duration_ms&quot;:30000)
  end

  test "widget interval_ms config overrides playlist + per-item", %{conn: conn} do
    d = display!("dtd3-#{System.unique_integer([:positive])}")
    pl = playlist_fixture()
    img = media_item_fixture(%{mime_type: "image/jpeg", duration_ms: nil})
    {:ok, _} = Playlists.add_item(pl, img.id)
    {:ok, _} = Playlists.update_settings(pl, %{transition_duration_ms: 7_000})
    slideshow_scene!(d.id, pl.id, %{"interval_ms" => 12_345})

    {:ok, _view, html} = live(conn, ~p"/d/#{d.id}")
    assert html =~ ~s(duration_ms&quot;:12345)
    refute html =~ ~s(duration_ms&quot;:7000)
  end

  test "widget config update patches slideshow data-items", %{conn: conn} do
    d = display!("dpatch-#{System.unique_integer([:positive])}")
    pl1 = playlist_fixture()
    pl2 = playlist_fixture()
    first = media_item_fixture(%{filename: "first-patched.jpg"})
    second = media_item_fixture(%{filename: "second-patched.jpg"})
    {:ok, _} = Playlists.add_item(pl1, first.id)
    {:ok, _} = Playlists.add_item(pl2, second.id)
    {_scene, inst} = slideshow_scene!(d.id, pl1.id)

    {:ok, view, html} = live(conn, ~p"/d/#{d.id}")
    assert html =~ "first-patched.jpg"
    refute html =~ "second-patched.jpg"

    {:ok, _} = Widgets.update_config(inst, %{"playlist_id" => pl2.id})

    html = render(view)
    assert html =~ "second-patched.jpg"
    refute html =~ "first-patched.jpg"
  end
end
