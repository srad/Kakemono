defmodule KakemonoWeb.Plugs.ApiAuth do
  @moduledoc """
  Validates `x-kakemono-secret` header against `:kakemono, :api_secret`.
  Uses Plug.Crypto.secure_compare/2.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.fetch_env!(:kakemono, :api_secret)

    case get_req_header(conn, "x-kakemono-secret") do
      [given] when is_binary(given) and is_binary(expected) ->
        if Plug.Crypto.secure_compare(given, expected) do
          conn
        else
          conn |> send_resp(401, "unauthorized") |> halt()
        end

      _ ->
        conn |> send_resp(401, "unauthorized") |> halt()
    end
  end
end
