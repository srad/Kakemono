defmodule Kakemono.Scenes.ScheduleWorker do
  @moduledoc """
  Oban.Cron entry: runs every minute. For each display, computes the currently
  scheduled scene and switches the display to it if it differs from the current one.
  Displays with no matching scheduled scene are left untouched.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Kakemono.{Displays, Scenes}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now =
      case args do
        %{"now" => iso} -> elem(DateTime.from_iso8601(iso), 1)
        _ -> DateTime.utc_now()
      end

    do_run(now)
  end

  @doc false
  def do_run(now) do
    scheduled = Scenes.active_for_now(nil, now)

    switched =
      Displays.list()
      |> Enum.count(fn display ->
        case scheduled do
          nil ->
            false

          %{id: sid} when sid != display.current_scene_id ->
            case Displays.set_scene(display.id, sid) do
              {:ok, _} -> true
              _ -> false
            end

          _ ->
            false
        end
      end)

    {:ok, switched}
  end
end
