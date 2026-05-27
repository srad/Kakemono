defmodule KakemonoWeb.ControlLiveSceneTest do
  use KakemonoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Kakemono.{Scenes, Displays, Fixtures}

  test "operator picks a scene from the display row dropdown", %{conn: conn} do
    d = Fixtures.display!("ctl-#{System.unique_integer([:positive])}")
    {:ok, p} = Scenes.create(%{name: "Morning", mode: "dashboard", layout: %{"cells" => []}})

    {:ok, view, _html} = live(conn, "/c")
    assert has_element?(view, "#scene-form-#{d.id}")

    view
    |> form("#scene-form-#{d.id}", %{display_id: d.id, scene_id: "#{p.id}"})
    |> render_change()

    assert Displays.get(d.id).current_scene_id == p.id
  end
end
