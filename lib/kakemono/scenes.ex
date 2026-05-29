defmodule Kakemono.Scenes do
  @moduledoc "Scenes context — saved display configurations (dashboard or fullscreen-widget)."
  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Scenes.Scene
  alias Kakemono.Displays

  @pubsub Kakemono.PubSub

  def list, do: Repo.all(from p in Scene, order_by: [asc: p.name])

  def get(id), do: Repo.get(Scene, id)
  def get!(id), do: Repo.get!(Scene, id)
  def get_by_name(name), do: Repo.get_by(Scene, name: name)

  def create(attrs) do
    %Scene{} |> Scene.changeset(attrs) |> Repo.insert()
  end

  def update(%Scene{} = p, attrs) do
    with {:ok, updated} <- p |> Scene.changeset(attrs) |> Repo.update() do
      broadcast_updated(updated.id)
      {:ok, updated}
    end
  end

  def delete(%Scene{} = p), do: Repo.delete(p)

  @doc """
  Activate `scene_id` on `display_id`. Delegates to `Displays.set_scene/2`,
  which performs the broadcast on `display:<id>`.
  """
  def set_active_for(display_id, scene_id) when is_binary(display_id) do
    Displays.set_scene(display_id, scene_id)
  end

  @doc """
  Compute the active scene for a display *right now* based on each scene's
  schedule. Returns nil if no scheduled scene matches. Phase 5 will wire this
  into `ScheduleWorker`; defined here so Phase 3 contracts stay stable.
  """
  def active_for_now(_display_id, now \\ DateTime.utc_now()) do
    list()
    |> Enum.filter(&schedule_matches?(&1, now))
    |> List.first()
  end

  defp schedule_matches?(%Scene{schedule: nil}, _now), do: false

  defp schedule_matches?(
         %Scene{schedule: %{"days" => days, "start_hour" => sh, "end_hour" => eh}},
         now
       ) do
    dow = Date.day_of_week(DateTime.to_date(now))
    hour = now.hour
    dow in days and hour >= sh and hour < eh
  end

  defp schedule_matches?(_, _), do: false

  defp broadcast_updated(scene_id) do
    Phoenix.PubSub.broadcast(@pubsub, "scene:#{scene_id}", {:scene_updated, scene_id})
  end
end
