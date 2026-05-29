defmodule KakemonoWeb.PageControllerTest do
  use KakemonoWeb.ConnCase

  test "GET / redirects to the control panel", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/c"
  end
end
