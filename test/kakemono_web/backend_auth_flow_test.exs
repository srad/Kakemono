defmodule KakemonoWeb.BackendAuthFlowTest do
  use KakemonoWeb.ConnCase, async: false

  @password "correct-horse-battery"

  setup do
    path =
      Path.join(System.tmp_dir!(), "kakemono_pw_flow_#{System.unique_integer([:positive])}.hash")

    prev_allow = Application.get_env(:kakemono, :allow_web_password_setup, true)
    Application.put_env(:kakemono, :backend_password_file, path)
    Application.put_env(:kakemono, :backend_auth, true)
    Application.put_env(:kakemono, :allow_web_password_setup, true)
    KakemonoWeb.LoginThrottle.reset()

    on_exit(fn ->
      File.rm_rf(path)
      Application.put_env(:kakemono, :backend_password_file, nil)
      Application.put_env(:kakemono, :backend_auth, false)
      Application.put_env(:kakemono, :allow_web_password_setup, prev_allow)
      KakemonoWeb.LoginThrottle.reset()
    end)

    :ok
  end

  test "control panel redirects unauthenticated requests to /login", %{conn: conn} do
    Kakemono.BackendAuth.set_password(@password)
    conn = get(conn, ~p"/c")
    assert redirected_to(conn) == ~p"/login"
  end

  test "landing page is also gated", %{conn: conn} do
    Kakemono.BackendAuth.set_password(@password)
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end

  test "correct password authenticates and grants access", %{conn: conn} do
    Kakemono.BackendAuth.set_password(@password)

    conn = post(conn, ~p"/login", %{"password" => @password})
    assert redirected_to(conn) == ~p"/c"

    conn = get(conn, ~p"/c/settings")
    assert html_response(conn, 200) =~ "Settings"
  end

  test "wrong password is rejected", %{conn: conn} do
    Kakemono.BackendAuth.set_password(@password)

    conn = post(conn, ~p"/login", %{"password" => "nope"})
    assert html_response(conn, 200) =~ "Incorrect password"
  end

  test "first-run sets the password when none configured and web setup allowed", %{conn: conn} do
    refute Kakemono.BackendAuth.configured?()

    conn = post(conn, ~p"/login", %{"password" => "fresh-password-1234"})
    assert redirected_to(conn) == ~p"/c"
    assert Kakemono.BackendAuth.configured?()
    assert Kakemono.BackendAuth.verify("fresh-password-1234")
  end

  test "too-short first-run password is rejected", %{conn: conn} do
    refute Kakemono.BackendAuth.configured?()

    conn = post(conn, ~p"/login", %{"password" => "short"})
    assert html_response(conn, 200) =~ "at least"
    refute Kakemono.BackendAuth.configured?()
  end

  test "web password setup is refused when disabled", %{conn: conn} do
    Application.put_env(:kakemono, :allow_web_password_setup, false)
    refute Kakemono.BackendAuth.configured?()

    conn = post(conn, ~p"/login", %{"password" => "fresh-password-1234"})
    assert html_response(conn, 200) =~ "not provisioned"
    refute Kakemono.BackendAuth.configured?()
  end

  test "login throttle returns 429 after repeated failures", %{conn: base_conn} do
    Kakemono.BackendAuth.set_password(@password)

    for _ <- 1..10 do
      conn = post(base_conn, ~p"/login", %{"password" => "wrong"})
      assert html_response(conn, 200) =~ "Incorrect password"
    end

    conn = post(base_conn, ~p"/login", %{"password" => "wrong"})
    assert response(conn, 429) =~ "Too many attempts"
  end

  test "logout clears the session", %{conn: conn} do
    Kakemono.BackendAuth.set_password(@password)

    conn = post(conn, ~p"/login", %{"password" => @password})
    conn = delete(conn, ~p"/logout")
    assert redirected_to(conn) == ~p"/login"

    conn = get(conn, ~p"/c")
    assert redirected_to(conn) == ~p"/login"
  end
end
