defmodule KakemonoWeb.Phase6Test do
  use KakemonoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Kakemono.Fixtures

  alias Kakemono.{Displays, Scenes}

  # ---------------------------------------------------------------------------
  # p6-url-overrides
  # ---------------------------------------------------------------------------

  describe "?scene= URL override" do
    setup do
      display_fixture(id: "p6-tablet")
      :ok
    end

    test "renders the named scene instead of the assigned one", %{conn: conn} do
      {:ok, _morning} =
        Scenes.create(%{name: "Morning", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, evening} =
        Scenes.create(%{name: "Evening", mode: "dashboard", layout: %{"cells" => []}})

      Displays.set_scene("p6-tablet", evening.id)

      {:ok, _view, html} = live(conn, "/d/p6-tablet?scene=Morning")
      assert html =~ "Morning"
    end

    test "ignores :scene_changed PubSub when override is active", %{conn: conn} do
      {:ok, _morning} =
        Scenes.create(%{name: "Override", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, other} =
        Scenes.create(%{name: "Other", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, view, _html} = live(conn, "/d/p6-tablet?scene=Override")

      Displays.set_scene("p6-tablet", other.id)
      html = render(view)
      assert html =~ "Override"
      refute html =~ ~r/Other.*has no widgets/
    end

    test "falls back to assigned scene when override name does not exist", %{conn: conn} do
      {:ok, assigned} =
        Scenes.create(%{name: "Assigned", mode: "dashboard", layout: %{"cells" => []}})

      Displays.set_scene("p6-tablet", assigned.id)

      {:ok, _view, html} = live(conn, "/d/p6-tablet?scene=NonExistent")
      assert html =~ "Assigned"
    end
  end

  # ---------------------------------------------------------------------------
  # p6-settings
  # ---------------------------------------------------------------------------

  describe "/c/settings" do
    test "shows the current API secret", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/c/settings")
      secret = Application.get_env(:kakemono, :api_secret)
      assert html =~ secret
    end

    test "regenerate changes the secret in Application env", %{conn: conn} do
      old_secret = Application.get_env(:kakemono, :api_secret)
      on_exit(fn -> Application.put_env(:kakemono, :api_secret, old_secret) end)

      {:ok, view, _html} = live(conn, "/c/settings")

      render_click(view, "regenerate")

      new_secret = Application.get_env(:kakemono, :api_secret)
      assert new_secret != old_secret
      assert render(view) =~ new_secret
    end
  end

  # ---------------------------------------------------------------------------
  # p6-fully-kiosk — PubSub broadcast reaches display LiveView
  # ---------------------------------------------------------------------------

  describe "Fully Kiosk broadcast" do
    setup do
      display_fixture(id: "fk-display")
      :ok
    end

    test "fk_cmd event broadcasts to the display topic", %{conn: conn} do
      {:ok, _display_view, _html} = live(conn, "/d/fk-display")
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:fk-display")

      conn2 = build_conn()
      {:ok, ctrl_view, _html} = live(conn2, "/c")

      render_click(ctrl_view, "fk_cmd", %{"display_id" => "fk-display", "cmd" => "screenOn"})

      assert_receive {:fully_kiosk_cmd, "screenOn"}, 500
    end
  end
end
