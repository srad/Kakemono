defmodule KakemonoWeb.ControlLiveTest do
  use KakemonoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Kakemono.Fixtures

  test "lists displays with offline indicator by default", %{conn: conn} do
    d = Fixtures.display!("ctl-#{System.unique_integer([:positive])}")
    {:ok, _view, html} = live(conn, ~p"/c")
    assert html =~ d.name
    assert html =~ ~s(data-display-id="#{d.id}")
    assert html =~ ~s(data-state="offline")
    assert html =~ ~s(href="/d/#{d.id}")
  end

  test "shows online indicator after heartbeat", %{conn: conn} do
    d = Fixtures.display!("ctl-#{System.unique_integer([:positive])}")
    {:ok, _} = Kakemono.Displays.heartbeat(d.id)
    {:ok, view, _html} = live(conn, ~p"/c")
    # trigger re-render via broadcast
    Phoenix.PubSub.broadcast(Kakemono.PubSub, "displays", {:display_updated, d})
    html = render(view)
    assert html =~ ~s(data-display-id="#{d.id}")
    assert html =~ ~s(data-state="online")
  end

  describe "create display form" do
    test "adds a new display", %{conn: conn} do
      id = "new-#{System.unique_integer([:positive])}"
      {:ok, view, _html} = live(conn, ~p"/c")

      html =
        view
        |> element("#create-display-form")
        |> render_submit(%{"display" => %{"id" => id, "name" => "My Display"}})

      assert html =~ "My Display"
      assert html =~ ~s(data-display-id="#{id}")
      assert Kakemono.Displays.get(id).name == "My Display"
    end

    test "rejects an invalid id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c")

      html =
        view
        |> element("#create-display-form")
        |> render_submit(%{"display" => %{"id" => "Bad ID!", "name" => ""}})

      assert html =~ "ID must match"
      refute Kakemono.Displays.get("Bad ID!")
    end

    test "rejects duplicate id", %{conn: conn} do
      d = Kakemono.Fixtures.display!("dupe-#{System.unique_integer([:positive])}")
      {:ok, view, _html} = live(conn, ~p"/c")

      html =
        view
        |> element("#create-display-form")
        |> render_submit(%{"display" => %{"id" => d.id, "name" => "x"}})

      assert html =~ "already exists"
    end
  end
end
