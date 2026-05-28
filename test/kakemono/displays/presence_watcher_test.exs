defmodule Kakemono.Displays.PresenceWatcherTest do
  use Kakemono.DataCase, async: false
  use Oban.Testing, repo: Kakemono.Repo, engine: Oban.Engines.Lite, notifier: Oban.Notifiers.PG

  alias Kakemono.Displays
  alias Kakemono.Displays.PresenceWatcher
  alias Kakemono.Fixtures

  test "broadcasts :display_updated for displays past the offline threshold" do
    stale_d = Fixtures.display!("stale-#{System.unique_integer([:positive])}")
    fresh_d = Fixtures.display!("fresh-#{System.unique_integer([:positive])}")

    stale_ts =
      DateTime.add(DateTime.utc_now(), -(Displays.offline_after_seconds() + 120), :second)
      |> DateTime.truncate(:second)

    {:ok, _} = Kakemono.Repo.update(Ecto.Changeset.change(stale_d, last_heartbeat_at: stale_ts))
    {:ok, _} = Displays.heartbeat(fresh_d.id)

    Phoenix.PubSub.subscribe(Kakemono.PubSub, "displays")
    assert :ok = perform_job(PresenceWatcher, %{})

    stale_id = stale_d.id
    fresh_id = fresh_d.id
    assert_receive {:display_updated, %{id: ^stale_id}}, 500
    refute_receive {:display_updated, %{id: ^fresh_id}}, 200
  end
end
