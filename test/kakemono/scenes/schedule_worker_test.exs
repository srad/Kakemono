defmodule Kakemono.Scenes.ScheduleWorkerTest do
  use Kakemono.DataCase, async: false
  use Oban.Testing, repo: Kakemono.Repo, engine: Oban.Engines.Lite, notifier: Oban.Notifiers.PG

  alias Kakemono.{Displays, Scenes}
  alias Kakemono.Scenes.ScheduleWorker
  alias Kakemono.Fixtures

  defp run_at(now), do: perform_job(ScheduleWorker, %{"now" => DateTime.to_iso8601(now)})

  describe "perform/1" do
    test "switches displays to the currently active scheduled scene" do
      d1 = Fixtures.display!("sw-d1-#{System.unique_integer([:positive])}")
      d2 = Fixtures.display!("sw-d2-#{System.unique_integer([:positive])}")

      now = ~U[2026-05-21 09:00:00Z]
      dow = Date.day_of_week(DateTime.to_date(now))

      {:ok, scene} =
        Scenes.create(%{
          name: "Morning",
          mode: "dashboard",
          layout: %{"cells" => []},
          schedule: %{"days" => [dow], "start_hour" => 7, "end_hour" => 11}
        })

      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:#{d1.id}")
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:#{d2.id}")

      assert {:ok, 2} = run_at(now)

      assert Displays.get(d1.id).current_scene_id == scene.id
      assert Displays.get(d2.id).current_scene_id == scene.id
      sid = scene.id
      assert_receive {:scene_changed, ^sid}
    end

    test "does nothing when no scene schedule matches" do
      d = Fixtures.display!("sw-d3-#{System.unique_integer([:positive])}")

      {:ok, _} =
        Scenes.create(%{
          name: "Night",
          mode: "dashboard",
          layout: %{"cells" => []},
          schedule: %{"days" => [1, 2, 3, 4, 5, 6, 7], "start_hour" => 22, "end_hour" => 23}
        })

      now = ~U[2026-05-21 14:00:00Z]
      assert {:ok, 0} = run_at(now)
      assert Displays.get(d.id).current_scene_id == nil
    end

    test "skips displays already on the scheduled scene" do
      {:ok, scene} =
        Scenes.create(%{
          name: "Midday",
          mode: "dashboard",
          layout: %{"cells" => []},
          schedule: %{"days" => [1, 2, 3, 4, 5, 6, 7], "start_hour" => 0, "end_hour" => 23}
        })

      d = Fixtures.display!("sw-d4-#{System.unique_integer([:positive])}")
      Displays.set_scene(d.id, scene.id)

      now = ~U[2026-05-21 12:00:00Z]
      assert {:ok, 0} = run_at(now)
    end
  end
end
