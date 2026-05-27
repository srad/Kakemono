defmodule KakemonoWeb.ScenesLiveTest do
  use KakemonoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Kakemono.{Scenes, Widgets}

  describe "/c/scenes index" do
    test "lists scenes and creates new ones", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/c/scenes")
      assert render(view) =~ "No scenes yet"

      view
      |> form("#create-scene-form", %{scene: %{name: "Morning", mode: "dashboard"}})
      |> render_submit()

      assert render(view) =~ "Morning"

      assert [
               %{
                 name: "Morning",
                 aspect_ratio: "16:9",
                 orientation: "portrait",
                 color_scheme: "light"
               }
             ] =
               Scenes.list()
    end

    test "creates a scene with selected canvas settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/c/scenes")

      view
      |> form("#create-scene-form", %{
        scene: %{
          name: "Square",
          mode: "dashboard",
          aspect_ratio: "1:1",
          orientation: "landscape",
          color_scheme: "dark"
        }
      })
      |> render_submit()

      assert [
               %{
                 name: "Square",
                 aspect_ratio: "1:1",
                 orientation: "landscape",
                 color_scheme: "dark"
               }
             ] =
               Scenes.list()
    end

    test "shows form error on duplicate-blank name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/c/scenes")

      html =
        view
        |> form("#create-scene-form", %{scene: %{name: "", mode: "dashboard"}})
        |> render_submit()

      assert html =~ "can\'t be blank" or html =~ "name:"
    end
  end

  describe "/c/scenes/:id — create_and_place" do
    test "creates an instance and places it on the grid", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "create_and_place", %{"type" => "clock"})

      assert [%{widget_type: "clock", scene_id: sid}] = Widgets.list_instances()
      assert sid == scene.id
      updated = Scenes.get!(scene.id)

      assert [%{"widget_instance_id" => _, "x" => _, "y" => _, "w" => 2, "h" => 2}] =
               updated.layout["cells"]
    end

    test "an instance created on one scene does not appear in another scene's editor",
         %{conn: conn} do
      {:ok, a} = Scenes.create(%{name: "A", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, b} = Scenes.create(%{name: "B", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, view_a, _} = live(conn, "/c/scenes/#{a.id}")
      render_click(view_a, "create_and_place", %{"type" => "clock"})

      assert [_] = Widgets.list_instances_for(a.id)
      assert [] = Widgets.list_instances_for(b.id)
    end

    test "auto-places at first free 2×2 spot when one cell is already placed", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      {:ok, scene} =
        Scenes.update(scene, %{
          layout: %{
            "cells" => [
              %{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 2, "h" => 2}
            ]
          }
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")
      render_click(view, "create_and_place", %{"type" => "weather"})

      updated = Scenes.get!(scene.id)
      assert length(updated.layout["cells"]) == 2
      [first, second] = updated.layout["cells"]
      assert {first["x"], first["y"]} != {second["x"], second["y"]}
    end

    test "creates a feed as a draft and opens its required config form", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Feeds", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      html = render_click(view, "create_and_place", %{"type" => "rss"})

      [inst] = Widgets.list_instances_for(scene.id)
      assert inst.widget_type == "rss"
      assert inst.config == %{"max_items" => 5}
      assert html =~ "Configure Feed"
      assert html =~ "Feed URL *"
    end

    test "creates weather as a blank draft and opens its location config", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "Weather", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      html = render_click(view, "create_and_place", %{"type" => "weather"})

      [inst] = Widgets.list_instances_for(scene.id)
      assert inst.widget_type == "weather"
      assert inst.config == %{}
      assert html =~ "Configure Weather"
      assert html =~ "Location *"
    end

    test "creates clock without a timezone and opens its config form", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "Clock", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      html = render_click(view, "create_and_place", %{"type" => "clock"})

      [inst] = Widgets.list_instances_for(scene.id)
      assert inst.widget_type == "clock"
      refute Map.has_key?(inst.config, "timezone")
      assert html =~ "Configure Clock"
      assert html =~ "Title"
      assert html =~ "Timezone *"
      assert html =~ "Europe/Berlin"
    end
  end

  describe "/c/scenes/:id — cells_changed" do
    test "merges moved/resized cells into persisted layout", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      {:ok, scene} =
        Scenes.update(scene, %{
          layout: %{
            "cells" => [
              %{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 2, "h" => 2}
            ]
          }
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "cells_changed", %{
        "cells" => [%{"widget_instance_id" => clock.id, "x" => 4, "y" => 3, "w" => 3, "h" => 4}]
      })

      updated = Scenes.get!(scene.id)
      assert [%{"x" => 4, "y" => 3, "w" => 3, "h" => 4}] = updated.layout["cells"]
    end

    test "rejects cell that overflows the 12-col grid", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      {:ok, scene} =
        Scenes.update(scene, %{
          layout: %{
            "cells" => [
              %{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 2, "h" => 2}
            ]
          }
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "cells_changed", %{
        "cells" => [%{"widget_instance_id" => clock.id, "x" => 10, "y" => 0, "w" => 5, "h" => 2}]
      })

      assert Scenes.get!(scene.id).layout["cells"] == [
               %{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 2, "h" => 2}
             ]
    end
  end

  describe "/c/scenes/:id — remove_from_canvas" do
    test "drops cell but keeps widget instance", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      {:ok, scene} =
        Scenes.update(scene, %{
          layout: %{
            "cells" => [
              %{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 2, "h" => 2}
            ]
          }
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "remove_from_canvas", %{
        "widget_instance_id" => "#{clock.id}"
      })

      assert Scenes.get!(scene.id).layout["cells"] == []
      assert Widgets.get_instance(clock.id) != nil
    end
  end

  describe "/c/scenes/:id — rename_scene" do
    test "updates the scene name", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "Old Name", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      view
      |> form("form[phx-submit=rename_scene]", %{name: "New Name"})
      |> render_submit()

      assert Scenes.get!(scene.id).name == "New Name"
    end
  end

  describe "/c/scenes/:id — aspect ratio" do
    test "updates the scene aspect ratio", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      view
      |> form("form[phx-submit=set_canvas_settings]", %{
        aspect_ratio: "4:3",
        orientation: "portrait",
        color_scheme: "light"
      })
      |> render_submit()

      assert Scenes.get!(scene.id).aspect_ratio == "4:3"
    end

    test "updates canvas settings", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      view
      |> form("form[phx-submit=set_canvas_settings]", %{
        aspect_ratio: "16:10",
        orientation: "landscape",
        color_scheme: "dark"
      })
      |> render_submit()

      updated = Scenes.get!(scene.id)
      assert updated.aspect_ratio == "16:10"
      assert updated.orientation == "landscape"
      assert updated.color_scheme == "dark"
    end
  end

  describe "/c/scenes/:id — config editing" do
    test "open_config sets editing_id and shows modal", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "open_config", %{"widget_instance_id" => "#{inst.id}"})

      assert render(view) =~ "Configure"
    end

    test "save_config persists updated config", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "open_config", %{"widget_instance_id" => "#{inst.id}"})

      view
      |> form("form[phx-submit=save_config]", %{
        instance_id: inst.id,
        config: %{timezone: "Europe/Berlin", format: "12h"}
      })
      |> render_submit()

      updated = Widgets.get_instance!(inst.id)
      assert updated.config["timezone"] == "Europe/Berlin"
      assert updated.config["format"] == "12h"
    end

    test "save_config can set and clear optional clock title", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{"title" => "Berlin"})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "open_config", %{"widget_instance_id" => "#{inst.id}"})

      view
      |> form("form[phx-submit=save_config]", %{
        instance_id: inst.id,
        config: %{title: "", timezone: "Europe/Berlin", format: "24h"}
      })
      |> render_submit()

      updated = Widgets.get_instance!(inst.id)
      assert updated.config["title"] == ""
    end

    test "save_config rejects invalid clock timezone", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "open_config", %{"widget_instance_id" => "#{inst.id}"})

      html =
        view
        |> form("form[phx-submit=save_config]", %{
          instance_id: inst.id,
          config: %{timezone: "Mars/Olympus", format: "12h"}
        })
        |> render_submit()

      assert html =~ "Invalid timezone"
    end

    test "save_config persists weather location with coordinates", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, inst} = Widgets.create_instance("weather", scene.id, %{})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "open_config", %{"widget_instance_id" => "#{inst.id}"})

      # Bypass hidden-input value enforcement (the JS hook sets these client-side).
      view
      |> element("form[phx-submit=save_config]")
      |> render_submit(%{
        instance_id: inst.id,
        config: %{label: "Munich, Bavaria, Germany", latitude: "48.137", longitude: "11.576"}
      })

      updated = Widgets.get_instance!(inst.id)
      assert updated.config["label"] == "Munich, Bavaria, Germany"
      assert updated.config["latitude"] == 48.137
      assert updated.config["longitude"] == 11.576
    end

    test "save_config shows error for missing required field", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Dash", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, inst} = Widgets.create_instance("weather", scene.id, %{})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      render_click(view, "open_config", %{"widget_instance_id" => "#{inst.id}"})

      html =
        view
        |> element("form[phx-submit=save_config]")
        |> render_submit(%{
          instance_id: inst.id,
          config: %{latitude: "", longitude: "", label: ""}
        })

      assert html =~ "required"
    end
  end

  describe "/c/scenes/:id — delete_instance" do
    test "deletes instance and drops its cells", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{name: "P", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      {:ok, scene} =
        Scenes.update(scene, %{
          layout: %{
            "cells" => [
              %{"widget_instance_id" => clock.id, "x" => 0, "y" => 0, "w" => 6, "h" => 4}
            ]
          }
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      view
      |> element(~s|button[phx-click="delete_instance"][phx-value-id="#{clock.id}"]|)
      |> render_click()

      assert Scenes.get!(scene.id).layout["cells"] == []
      assert Widgets.get_instance(clock.id) == nil
    end
  end

  describe "/c/scenes/:id — fullscreen_widget mode" do
    test "create_and_place creates the instance and assigns it as the fullscreen widget",
         %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{
          name: "FS-new",
          mode: "fullscreen_widget",
          layout: %{"widget_instance_id" => 0}
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")
      render_click(view, "create_and_place", %{"type" => "clock"})

      [inst] = Widgets.list_instances_for(scene.id)
      assert inst.widget_type == "clock"
      assert Scenes.get!(scene.id).layout["widget_instance_id"] == inst.id
    end

    test "create_and_place deletes the previously-assigned fullscreen instance",
         %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{
          name: "FS-swap",
          mode: "fullscreen_widget",
          layout: %{"widget_instance_id" => 0}
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")
      render_click(view, "create_and_place", %{"type" => "clock"})
      [%{id: clock_id, widget_type: "clock"}] = Widgets.list_instances_for(scene.id)

      render_click(view, "create_and_place", %{"type" => "weather"})

      [remaining] = Widgets.list_instances_for(scene.id)
      assert remaining.widget_type == "weather"
      assert Widgets.get_instance(clock_id) == nil
      assert Scenes.get!(scene.id).layout["widget_instance_id"] == remaining.id
    end

    test "sets the fullscreen widget", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{
          name: "FS",
          mode: "fullscreen_widget",
          layout: %{"widget_instance_id" => 0}
        })

      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      view
      |> form("form[phx-submit=set_fullscreen_widget]", %{widget_instance_id: inst.id})
      |> render_submit()

      assert Scenes.get!(scene.id).layout["widget_instance_id"] == inst.id
    end
  end

  describe "/c/scenes/:id schedule" do
    test "saves a schedule and persists it", %{conn: conn} do
      {:ok, scene} = Scenes.create(%{name: "Sched", mode: "dashboard", layout: %{"cells" => []}})
      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      view
      |> form("form[phx-submit=save_schedule]", %{
        schedule: %{days: ["1", "2", "3", "4", "5"], start_hour: "7", end_hour: "10"}
      })
      |> render_submit()

      updated = Scenes.get!(scene.id)
      assert updated.schedule["days"] == [1, 2, 3, 4, 5]
      assert updated.schedule["start_hour"] == 7
      assert updated.schedule["end_hour"] == 10
    end

    test "clears a schedule", %{conn: conn} do
      {:ok, scene} =
        Scenes.create(%{
          name: "WithSched",
          mode: "dashboard",
          layout: %{"cells" => []},
          schedule: %{"days" => [1], "start_hour" => 8, "end_hour" => 9}
        })

      {:ok, view, _html} = live(conn, "/c/scenes/#{scene.id}")

      view
      |> element("button[phx-click='clear_schedule']")
      |> render_click()

      assert Scenes.get!(scene.id).schedule == nil
    end
  end
end
