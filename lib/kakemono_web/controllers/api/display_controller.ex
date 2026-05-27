defmodule KakemonoWeb.Api.DisplayController do
  use KakemonoWeb, :controller

  alias Kakemono.Displays

  def heartbeat(conn, %{"id" => id}) do
    case Displays.heartbeat(id) do
      {:ok, d} ->
        json(conn, %{ok: true, id: d.id, last_heartbeat_at: d.last_heartbeat_at})

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "unknown_display"})
    end
  end

  def set_scene(conn, %{"id" => id, "scene_id" => scene_id}) do
    pid = if is_binary(scene_id), do: String.to_integer(scene_id), else: scene_id

    case Displays.set_scene(id, pid) do
      {:ok, d} -> json(conn, %{ok: true, current_scene_id: d.current_scene_id})
      :error -> conn |> put_status(:not_found) |> json(%{error: "unknown_display"})
    end
  end

  def state(conn, %{"id" => id}) do
    case Displays.get(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "unknown_display"})

      d ->
        json(conn, %{
          id: d.id,
          name: d.name,
          online: Displays.online?(d),
          current_scene_id: d.current_scene_id,
          last_heartbeat_at: d.last_heartbeat_at
        })
    end
  end
end
