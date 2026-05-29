defmodule Kakemono.Displays do
  @moduledoc "Display registry and online/heartbeat tracking."
  alias Kakemono.Repo
  alias Kakemono.Displays.Display

  @offline_after_seconds 90

  def get(id), do: Repo.get(Display, id)
  def list, do: Repo.all(Display)

  def create(attrs) do
    case %Display{} |> Display.changeset(attrs) |> Repo.insert() do
      {:ok, d} = res ->
        broadcast(d, :created)
        res

      err ->
        err
    end
  end

  def upsert(attrs) do
    id = attrs[:id] || attrs["id"]

    case get(id) do
      nil ->
        create(attrs)

      d ->
        case d |> Display.changeset(attrs) |> Repo.update() do
          {:ok, updated} = res ->
            broadcast(updated, :updated)
            res

          err ->
            err
        end
    end
  end

  def delete(id) when is_binary(id) do
    case get(id) do
      nil ->
        :error

      %Display{} = d ->
        with {:ok, deleted} <- Repo.delete(d) do
          broadcast_deleted(deleted)
          {:ok, deleted}
        end
    end
  end

  @doc "Record a heartbeat. Returns {:ok, display} or :error if unknown."
  def heartbeat(id) when is_binary(id) do
    case get(id) do
      nil ->
        :error

      d ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        {:ok, updated} = d |> Display.changeset(%{last_heartbeat_at: now}) |> Repo.update()
        broadcast(updated, :heartbeat)
        {:ok, updated}
    end
  end

  @doc "Switch a display to a given scene and broadcast the change."
  def set_scene(id, scene_id) when is_binary(id) do
    case get(id) do
      nil ->
        :error

      d ->
        {:ok, updated} =
          d |> Display.changeset(%{current_scene_id: scene_id}) |> Repo.update()

        broadcast(updated, {:scene_changed, scene_id})
        {:ok, updated}
    end
  end

  @doc "True if the display sent a heartbeat in the last #{@offline_after_seconds}s."
  def online?(%Display{last_heartbeat_at: nil}), do: false

  def online?(%Display{last_heartbeat_at: ts}) do
    DateTime.diff(DateTime.utc_now(), ts) <= @offline_after_seconds
  end

  def online?(id) when is_binary(id) do
    case get(id) do
      nil -> false
      d -> online?(d)
    end
  end

  def offline_after_seconds, do: @offline_after_seconds

  defp broadcast(%Display{id: id} = d, msg) do
    Phoenix.PubSub.broadcast(Kakemono.PubSub, "display:#{id}", msg)
    Phoenix.PubSub.broadcast(Kakemono.PubSub, "displays", {:display_updated, d})
  end

  defp broadcast_deleted(%Display{id: id}) do
    Phoenix.PubSub.broadcast(Kakemono.PubSub, "display:#{id}", :deleted)
    Phoenix.PubSub.broadcast(Kakemono.PubSub, "displays", {:display_deleted, id})
  end
end
