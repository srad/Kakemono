defmodule KakemonoWeb.DisplayLiveSceneTest do
  use KakemonoWeb.ConnCase, async: false
  use Oban.Testing, repo: Kakemono.Repo, engine: Oban.Engines.Lite, notifier: Oban.Notifiers.PG
  import Phoenix.LiveViewTest
  alias Kakemono.{Calendars, Displays, Fixtures, Scenes, Widgets}
  alias Kakemono.Widgets.FetchWorker

  test "renders the dashboard scene grid with widgets when set", %{conn: conn} do
    d = Fixtures.display!("dash-#{System.unique_integer([:positive])}")

    {:ok, scene} =
      Scenes.create(%{name: "Dashy", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

    {:ok, scene} =
      Scenes.update(scene, %{
        layout: %{
          "cells" => [%{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 6, "h" => 4}]
        }
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    {:ok, _view, html} = live(conn, "/d/#{d.id}")

    assert html =~ "cell-#{clock.id}"
    assert html =~ "kakemono-widget-clock"
    assert html =~ "grid-column: 1 / span 6"
    assert html =~ "aspect-ratio: 9 / 16"
    assert html =~ "kw-shell-light"
    refute html =~ "kw-clock-title"
    refute html =~ "phx-hook=\"Slideshow\""
  end

  test "renders optional clock title when configured", %{conn: conn} do
    d = Fixtures.display!("clock-title-#{System.unique_integer([:positive])}")

    {:ok, scene} =
      Scenes.create(%{name: "Clock title", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, clock} =
      Widgets.create_instance("clock", scene.id, %{
        "title" => "Berlin",
        "timezone" => "Europe/Berlin"
      })

    {:ok, scene} =
      Scenes.update(scene, %{
        layout: %{
          "cells" => [%{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 6, "h" => 4}]
        }
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    {:ok, _view, html} = live(conn, "/d/#{d.id}")

    assert html =~ "kw-clock-title"
    assert html =~ "Berlin"
  end

  test "switches to scene view live on :scene_changed broadcast", %{conn: conn} do
    d = Fixtures.display!("switch-#{System.unique_integer([:positive])}")
    {:ok, _view, html} = live(conn, "/d/#{d.id}")
    assert html =~ "No scene assigned"

    {:ok, scene} =
      Scenes.create(%{name: "Live-switch", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

    {:ok, scene} =
      Scenes.update(scene, %{
        layout: %{
          "cells" => [
            %{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 12, "h" => 12}
          ]
        }
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    {:ok, _view2, html2} = live(conn, "/d/#{d.id}")
    assert html2 =~ "kakemono-widget-clock"
  end

  test "auto-prefetches data for widgets with empty cache on first view", %{conn: conn} do
    d = Fixtures.display!("prefetch-#{System.unique_integer([:positive])}")

    {:ok, scene} =
      Scenes.create(%{name: "Prefetch", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, weather} =
      Widgets.create_instance("weather", scene.id, %{
        "latitude" => 48.137,
        "longitude" => 11.576
      })

    {:ok, scene} =
      Scenes.update(scene, %{
        layout: %{
          "cells" => [
            %{"widget_instance_id" => weather.id, "x" => 0, "y" => 0, "w" => 6, "h" => 4}
          ]
        }
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    refute_enqueued(worker: FetchWorker, args: %{instance_id: weather.id})

    {:ok, _view, _html} = live(conn, "/d/#{d.id}")

    assert_enqueued(worker: FetchWorker, args: %{instance_id: weather.id})
  end

  test "widget config updates refresh the connected display", %{conn: conn} do
    d = Fixtures.display!("rss-refresh-#{System.unique_integer([:positive])}")

    {:ok, scene} =
      Scenes.create(%{name: "RSS Refresh", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, rss} =
      Widgets.create_instance("rss", scene.id, %{
        "url" => "http://example.com/old",
        "cached_items" => [
          %{"title" => "Old Item", "link" => "http://example.com/old", "pub_date" => ""}
        ],
        "feed_title" => "Old Feed",
        "fetched_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
      })

    {:ok, scene} =
      Scenes.update(scene, %{
        layout: %{
          "cells" => [%{"widget_instance_id" => rss.id, "x" => 0, "y" => 0, "w" => 6, "h" => 4}]
        }
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    {:ok, view, html} = live(conn, "/d/#{d.id}")
    assert html =~ "Old Item"

    assert {:ok, updated} = Widgets.update_config(rss, %{"url" => "http://example.com/new"})
    refute Map.has_key?(updated.config, "cached_items")

    html = render(view)
    assert html =~ "No items cached yet."
    refute html =~ "Old Item"
    assert_enqueued(worker: FetchWorker, args: %{instance_id: rss.id})
  end

  test "scene settings updates refresh the connected display", %{conn: conn} do
    d = Fixtures.display!("scene-refresh-#{System.unique_integer([:positive])}")

    {:ok, scene} =
      Scenes.create(%{
        name: "Scene Settings Refresh",
        mode: "dashboard",
        layout: %{"cells" => []},
        aspect_ratio: "16:9",
        orientation: "portrait",
        color_scheme: "light"
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    {:ok, view, html} = live(conn, "/d/#{d.id}")
    assert html =~ "aspect-ratio: 9 / 16"
    assert html =~ "kw-shell-light"

    {:ok, _updated} =
      Scenes.update(scene, %{
        orientation: "landscape",
        color_scheme: "dark"
      })

    html = render(view)
    assert html =~ "aspect-ratio: 16 / 9"
    assert html =~ "kw-shell-dark"
  end

  test "fullscreen_widget mode renders a single widget filling the grid", %{conn: conn} do
    d = Fixtures.display!("fs-#{System.unique_integer([:positive])}")

    {:ok, scene} =
      Scenes.create(%{
        name: "FS",
        mode: "fullscreen_widget",
        layout: %{"widget_instance_id" => 0}
      })

    {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

    {:ok, scene} =
      Scenes.update(scene, %{layout: %{"widget_instance_id" => clock.id}})

    {:ok, _} = Displays.set_scene(d.id, scene.id)
    {:ok, _view, html} = live(conn, "/d/#{d.id}")

    assert html =~ "kakemono-widget-clock"
    assert html =~ "grid-column: 1 / span 12"
  end

  test "renders updated calendar widget events after event changes", %{conn: conn} do
    d = Fixtures.display!("calendar-#{System.unique_integer([:positive])}")
    calendar = Fixtures.calendar_fixture(%{name: "Family"})

    event =
      Fixtures.calendar_event_fixture(calendar, %{
        title: "Breakfast",
        start_on: "2026-05-30",
        start_time: "09:00",
        end_on: "2026-05-30",
        end_time: "10:00"
      })

    {:ok, scene} = Scenes.create(%{name: "Calendar", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, widget} =
      Widgets.create_instance("calendar", scene.id, %{
        "calendar_id" => calendar.id
      })

    {:ok, scene} =
      Scenes.update(scene, %{
        layout: %{
          "cells" => [
            %{"widget_instance_id" => widget.id, "x" => 0, "y" => 0, "w" => 6, "h" => 4}
          ]
        }
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    Application.put_env(:kakemono, :calendar_now_fn, fn -> ~U[2026-05-30 08:00:00Z] end)
    on_exit(fn -> Application.delete_env(:kakemono, :calendar_now_fn) end)

    {:ok, _view, html} = live(conn, "/d/#{d.id}")
    assert html =~ "kakemono-widget-calendar"
    assert html =~ "kw-calendar-grid"
    assert html =~ "Breakfast"

    assert {:ok, _updated} =
             Calendars.update_event(event, %{
               title: "Brunch",
               start_on: "2026-05-30",
               start_time: "09:00",
               end_on: "2026-05-30",
               end_time: "10:00",
               recurrence: "none",
               recurrence_interval: "1"
             })

    {:ok, _view2, html} = live(conn, "/d/#{d.id}")
    assert html =~ "Brunch"
    refute html =~ "Breakfast"
  end

  test "calendar agenda widget shows the current event when time advances", %{conn: conn} do
    d = Fixtures.display!("calendar-tick-#{System.unique_integer([:positive])}")
    calendar = Fixtures.calendar_fixture(%{name: "Office"})

    Fixtures.calendar_event_fixture(calendar, %{
      title: "Standup",
      start_on: "2026-05-30",
      start_time: "09:30",
      end_on: "2026-05-30",
      end_time: "10:00"
    })

    {:ok, scene} =
      Scenes.create(%{name: "Focus calendar", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, widget} =
      Widgets.create_instance("calendar", scene.id, %{
        "calendar_id" => calendar.id,
        "view_mode" => "agenda"
      })

    {:ok, scene} =
      Scenes.update(scene, %{
        layout: %{
          "cells" => [
            %{"widget_instance_id" => widget.id, "x" => 0, "y" => 0, "w" => 6, "h" => 4}
          ]
        }
      })

    {:ok, _} = Displays.set_scene(d.id, scene.id)

    Application.put_env(:kakemono, :calendar_now_fn, fn -> ~U[2026-05-30 09:00:00Z] end)
    on_exit(fn -> Application.delete_env(:kakemono, :calendar_now_fn) end)

    {:ok, _view, html} = live(conn, "/d/#{d.id}")
    assert html =~ "Standup"
    refute html =~ "Now"

    Application.put_env(:kakemono, :calendar_now_fn, fn -> ~U[2026-05-30 09:31:00Z] end)

    {:ok, _view2, html} = live(conn, "/d/#{d.id}")
    assert html =~ "Now"
  end
end
