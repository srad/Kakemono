defmodule KakemonoWeb.SessionController do
  use KakemonoWeb, :controller

  alias Kakemono.BackendAuth
  alias KakemonoWeb.LoginThrottle

  def new(conn, _params) do
    render(conn, :new,
      configured: BackendAuth.configured?(),
      allow_setup: allow_web_password_setup?(),
      page_title: "Login"
    )
  end

  def create(conn, %{"password" => password}) do
    case LoginThrottle.check() do
      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> put_flash(:error, "Too many attempts. Try again shortly.")
        |> render(:new,
          configured: BackendAuth.configured?(),
          allow_setup: allow_web_password_setup?(),
          page_title: "Login"
        )

      :ok ->
        if BackendAuth.configured?() do
          authenticate(conn, password)
        else
          setup(conn, password)
        end
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:backend_authed)
    |> put_flash(:info, "Logged out")
    |> redirect(to: ~p"/login")
  end

  defp authenticate(conn, password) do
    if BackendAuth.verify(password) do
      LoginThrottle.reset()
      authed(conn)
    else
      LoginThrottle.record_failure()

      conn
      |> put_flash(:error, "Incorrect password")
      |> render(:new,
        configured: true,
        allow_setup: allow_web_password_setup?(),
        page_title: "Login"
      )
    end
  end

  defp setup(conn, password) do
    if allow_web_password_setup?() do
      case BackendAuth.set_password(String.trim(password)) do
        :ok ->
          authed(conn)

        {:error, :too_short} ->
          conn
          |> put_flash(
            :error,
            "Password must be at least #{BackendAuth.min_password_length()} characters"
          )
          |> render(:new, configured: false, allow_setup: true, page_title: "Login")

        {:error, _} ->
          conn
          |> put_flash(:error, "Could not set password")
          |> render(:new, configured: false, allow_setup: true, page_title: "Login")
      end
    else
      conn
      |> put_flash(:error, "Backend not provisioned")
      |> render(:new, configured: false, allow_setup: false, page_title: "Login")
    end
  end

  defp authed(conn) do
    return_to = get_session(conn, :backend_return_to) || ~p"/c"

    conn
    |> configure_session(renew: true)
    |> delete_session(:backend_return_to)
    |> put_session(:backend_authed, true)
    |> redirect(to: return_to)
  end

  defp allow_web_password_setup?,
    do: Application.get_env(:kakemono, :allow_web_password_setup, true)
end
