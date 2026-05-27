defmodule KakemonoWeb.BackupController do
  use KakemonoWeb, :controller

  alias Kakemono.Backup

  def download(conn, %{"filename" => filename}) do
    case Backup.path_for(filename) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("Not found")

      path ->
        if File.exists?(path) do
          send_download(conn, {:file, path}, filename: filename)
        else
          conn
          |> put_status(:not_found)
          |> text("Not found")
        end
    end
  end
end
