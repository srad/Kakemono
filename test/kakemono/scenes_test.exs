defmodule Kakemono.ScenesTest do
  use Kakemono.DataCase, async: false
  alias Kakemono.Scenes

  describe "create/1" do
    test "creates a dashboard scene with valid layout" do
      assert {:ok, p} =
               Scenes.create(%{
                 name: "Morning",
                 mode: "dashboard",
                 layout: %{
                   "cells" => [
                     %{"widget_instance_id" => 1, "x" => 0, "y" => 0, "w" => 6, "h" => 4}
                   ]
                 }
               })

      assert p.id
      assert p.mode == "dashboard"
      assert p.aspect_ratio == "16:9"
      assert p.orientation == "portrait"
      assert p.color_scheme == "light"
    end

    test "creates a scene with supported canvas settings" do
      assert {:ok, p} =
               Scenes.create(%{
                 name: "Square",
                 mode: "dashboard",
                 layout: %{"cells" => []},
                 aspect_ratio: "1:1",
                 orientation: "landscape",
                 color_scheme: "dark"
               })

      assert p.aspect_ratio == "1:1"
      assert p.orientation == "landscape"
      assert p.color_scheme == "dark"
    end

    test "rejects unsupported aspect ratio" do
      assert {:error, cs} =
               Scenes.create(%{
                 name: "Tall",
                 mode: "dashboard",
                 layout: %{"cells" => []},
                 aspect_ratio: "9:16"
               })

      assert "is invalid" in errors_on(cs).aspect_ratio
    end

    test "rejects unsupported orientation and color scheme" do
      assert {:error, cs} =
               Scenes.create(%{
                 name: "Bad canvas",
                 mode: "dashboard",
                 layout: %{"cells" => []},
                 orientation: "diagonal",
                 color_scheme: "sepia"
               })

      errors = errors_on(cs)
      assert "is invalid" in errors.orientation
      assert "is invalid" in errors.color_scheme
    end

    test "rejects unknown mode" do
      assert {:error, cs} = Scenes.create(%{name: "X", mode: "blink", layout: %{"cells" => []}})
      assert "is invalid" in errors_on(cs).mode
    end

    test "rejects cell that overflows 12-col grid" do
      assert {:error, cs} =
               Scenes.create(%{
                 name: "Wide",
                 mode: "dashboard",
                 layout: %{
                   "cells" => [
                     %{"widget_instance_id" => 1, "x" => 10, "y" => 0, "w" => 5, "h" => 1}
                   ]
                 }
               })

      assert Map.has_key?(errors_on(cs), :layout)
    end

    test "rejects cell that overflows 12-row grid" do
      assert {:error, cs} =
               Scenes.create(%{
                 name: "Tall",
                 mode: "dashboard",
                 layout: %{
                   "cells" => [
                     %{"widget_instance_id" => 1, "x" => 0, "y" => 11, "w" => 2, "h" => 2}
                   ]
                 }
               })

      assert Map.has_key?(errors_on(cs), :layout)
    end

    test "fullscreen_widget mode requires widget_instance_id in layout" do
      assert {:error, cs} =
               Scenes.create(%{name: "FS", mode: "fullscreen_widget", layout: %{"cells" => []}})

      assert Map.has_key?(errors_on(cs), :layout)

      assert {:ok, _p} =
               Scenes.create(%{
                 name: "FS-good",
                 mode: "fullscreen_widget",
                 layout: %{"widget_instance_id" => 1}
               })
    end

    test "schedule shape is validated when present" do
      assert {:error, cs} =
               Scenes.create(%{
                 name: "Sched",
                 mode: "dashboard",
                 layout: %{"cells" => []},
                 schedule: %{"days" => [0, 8], "start_hour" => 9, "end_hour" => 10}
               })

      assert Map.has_key?(errors_on(cs), :schedule)
    end
  end

  describe "set_active_for/2" do
    test "delegates to Displays.set_scene/2 and broadcasts" do
      d = Kakemono.Fixtures.display!("d-#{System.unique_integer([:positive])}")
      {:ok, p} = Scenes.create(%{name: "Scene X", mode: "dashboard", layout: %{"cells" => []}})

      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:" <> d.id)
      assert {:ok, updated} = Scenes.set_active_for(d.id, p.id)
      assert updated.current_scene_id == p.id

      pid = p.id
      assert_receive {:scene_changed, ^pid}
    end

    test "returns :error for unknown display" do
      {:ok, p} = Scenes.create(%{name: "Scene Y", mode: "dashboard", layout: %{"cells" => []}})
      assert Scenes.set_active_for("nope", p.id) == :error
    end
  end

  describe "active_for_now/2" do
    test "returns nil when no scene has a matching schedule" do
      _ = Scenes.create(%{name: "No-sched", mode: "dashboard", layout: %{"cells" => []}})
      assert Scenes.active_for_now("tablet") == nil
    end

    test "returns a scene whose schedule covers `now`" do
      now = ~U[2026-05-21 10:00:00Z]
      dow = Date.day_of_week(DateTime.to_date(now))

      {:ok, _miss} =
        Scenes.create(%{
          name: "Evening",
          mode: "dashboard",
          layout: %{"cells" => []},
          schedule: %{"days" => [dow], "start_hour" => 18, "end_hour" => 22}
        })

      {:ok, hit} =
        Scenes.create(%{
          name: "Morning",
          mode: "dashboard",
          layout: %{"cells" => []},
          schedule: %{"days" => [dow], "start_hour" => 8, "end_hour" => 12}
        })

      assert %{id: pid} = Scenes.active_for_now("tablet", now)
      assert pid == hit.id
    end
  end
end
