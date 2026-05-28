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
    case parse_scene_id(scene_id) do
      {:ok, pid} ->
        case Displays.set_scene(id, pid) do
          {:ok, d} -> json(conn, %{ok: true, current_scene_id: d.current_scene_id})
          :error -> conn |> put_status(:not_found) |> json(%{error: "unknown_display"})
        end

      :error ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_scene_id"})
    end
  end

  # nil clears the scene; integers pass through; strings must parse cleanly.
  defp parse_scene_id(nil), do: {:ok, nil}
  defp parse_scene_id(scene_id) when is_integer(scene_id), do: {:ok, scene_id}

  defp parse_scene_id(scene_id) when is_binary(scene_id) do
    case Integer.parse(scene_id) do
      {pid, ""} -> {:ok, pid}
      _ -> :error
    end
  end

  defp parse_scene_id(_), do: :error

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
