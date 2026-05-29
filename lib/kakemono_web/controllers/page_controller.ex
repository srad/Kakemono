defmodule KakemonoWeb.PageController do
  use KakemonoWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/c")
  end
end
