defmodule KakemonoWeb.Plugs.BackendAuth do
  @moduledoc """
  Gates backend routes behind the single backend password.

  Unauthenticated requests are redirected to `/login`, remembering the original
  path so the login flow can return there. Passes through when backend auth is
  disabled (test/opt-out). LiveView mounts are checked separately by
  `KakemonoWeb.BackendAuth.on_mount/4`.
  """
  use KakemonoWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      not Kakemono.BackendAuth.enabled?() ->
        conn

      get_session(conn, :backend_authed) ->
        conn

      true ->
        conn
        |> put_session(:backend_return_to, conn.request_path)
        |> redirect(to: ~p"/login")
        |> halt()
    end
  end
end
