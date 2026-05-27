defmodule KakemonoWeb.Api.DisplayControllerTest do
  use KakemonoWeb.ConnCase, async: false

  alias Kakemono.Fixtures

  @secret "test-secret"

  defp auth(conn), do: put_req_header(conn, "x-kakemono-secret", @secret)

  describe "auth" do
    test "401 without header", %{conn: conn} do
      d = Fixtures.display!("a-#{System.unique_integer([:positive])}")
      conn = post(conn, ~p"/api/displays/#{d.id}/heartbeat")
      assert response(conn, 401)
    end

    test "401 with wrong header", %{conn: conn} do
      d = Fixtures.display!("a-#{System.unique_integer([:positive])}")

      conn =
        conn
        |> put_req_header("x-kakemono-secret", "wrong")
        |> post(~p"/api/displays/#{d.id}/heartbeat")

      assert response(conn, 401)
    end
  end

  describe "heartbeat" do
    test "updates last_heartbeat_at", %{conn: conn} do
      d = Fixtures.display!("hb-#{System.unique_integer([:positive])}")
      conn = conn |> auth() |> post(~p"/api/displays/#{d.id}/heartbeat")
      assert %{"ok" => true, "id" => id} = json_response(conn, 200)
      assert id == d.id
      assert Kakemono.Displays.get(d.id).last_heartbeat_at != nil
    end

    test "404 for unknown display", %{conn: conn} do
      conn = conn |> auth() |> post(~p"/api/displays/nope/heartbeat")
      assert json_response(conn, 404)["error"] == "unknown_display"
    end
  end

  describe "set_scene" do
    test "updates current_scene_id", %{conn: conn} do
      d = Fixtures.display!("sp-#{System.unique_integer([:positive])}")
      scene = Fixtures.scene_fixture()
      conn = conn |> auth() |> post(~p"/api/displays/#{d.id}/scene", %{"scene_id" => scene.id})
      assert %{"ok" => true, "current_scene_id" => pid} = json_response(conn, 200)
      assert pid == scene.id
    end
  end

  describe "state" do
    test "returns display metadata including online flag", %{conn: conn} do
      d = Fixtures.display!("st-#{System.unique_integer([:positive])}")
      {:ok, _} = Kakemono.Displays.heartbeat(d.id)
      conn = conn |> auth() |> get(~p"/api/displays/#{d.id}")
      body = json_response(conn, 200)
      assert body["id"] == d.id
      assert body["online"] == true
    end
  end
end
