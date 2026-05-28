defmodule KakemonoWeb.SessionHTML do
  @moduledoc """
  Templates rendered by SessionController (login / first-run password setup).
  """
  use KakemonoWeb, :html

  embed_templates "session_html/*"
end
