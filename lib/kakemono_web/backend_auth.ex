defmodule KakemonoWeb.BackendAuth do
  @moduledoc """
  LiveView `on_mount` hook enforcing the backend password on the socket.

  The request plug (`KakemonoWeb.Plugs.BackendAuth`) only protects the initial
  dead render; LiveView mounts over the websocket and must be checked here too.
  """
  use KakemonoWeb, :verified_routes

  import Phoenix.LiveView, only: [redirect: 2]

  def on_mount(:ensure_authed, _params, session, socket) do
    if not Kakemono.BackendAuth.enabled?() or session["backend_authed"] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/login")}
    end
  end
end
