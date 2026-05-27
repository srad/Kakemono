defmodule KakemonoWeb.DisplayLiveSceneTest do
  use KakemonoWeb.ConnCase, async: false
  use Oban.Testing, repo: Kakemono.Repo
  import Phoenix.LiveViewTest
  alias Kakemono.{Scenes, Widgets, Displays, Fixtures}
  alias Kakemono.Widgets.WeatherFetchWorker

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

    refute_enqueued(worker: WeatherFetchWorker, args: %{instance_id: weather.id})

    {:ok, _view, _html} = live(conn, "/d/#{d.id}")

    assert_enqueued(worker: WeatherFetchWorker, args: %{instance_id: weather.id})
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
end
