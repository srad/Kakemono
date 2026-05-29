defmodule Kakemono.DisplaysTest do
  use Kakemono.DataCase, async: false

  alias Kakemono.Displays
  alias Kakemono.Fixtures

  describe "heartbeat/1" do
    test "updates last_heartbeat_at and broadcasts" do
      d = Fixtures.display!("tablet-#{System.unique_integer([:positive])}")
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "displays")

      assert {:ok, updated} = Displays.heartbeat(d.id)
      assert updated.last_heartbeat_at != nil
      did = d.id
      assert_receive {:display_updated, %{id: ^did}}, 500
    end

    test "returns :error for unknown id" do
      assert Displays.heartbeat("nope") == :error
    end
  end

  describe "set_scene/2" do
    test "updates current_scene_id and broadcasts :scene_changed" do
      d = Fixtures.display!("tv-#{System.unique_integer([:positive])}")
      scene = Fixtures.scene_fixture()
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:#{d.id}")

      assert {:ok, updated} = Displays.set_scene(d.id, scene.id)
      assert updated.current_scene_id == scene.id
      pid = scene.id
      assert_receive {:scene_changed, ^pid}, 500
    end

    test "returns :error for unknown id" do
      assert Displays.set_scene("nope", 1) == :error
    end
  end

  describe "online?/1" do
    test "false when last_heartbeat_at is nil" do
      d = Fixtures.display!("d1-#{System.unique_integer([:positive])}")
      refute Displays.online?(d)
    end

    test "true when last_heartbeat_at is recent" do
      d = Fixtures.display!("d2-#{System.unique_integer([:positive])}")
      {:ok, d2} = Displays.heartbeat(d.id)
      assert Displays.online?(d2)
      assert Displays.online?(d2.id)
    end

    test "false when last_heartbeat_at is older than threshold" do
      d = Fixtures.display!("d3-#{System.unique_integer([:positive])}")

      stale =
        DateTime.add(DateTime.utc_now(), -(Displays.offline_after_seconds() + 60), :second)
        |> DateTime.truncate(:second)

      {:ok, d2} = Kakemono.Repo.update(Ecto.Changeset.change(d, last_heartbeat_at: stale))
      refute Displays.online?(d2)
    end
  end

  describe "create/1 and upsert/1" do
    test "create/1 broadcasts on the displays topic" do
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "displays")
      id = "new-#{System.unique_integer([:positive])}"
      assert {:ok, _d} = Displays.create(%{id: id, name: "X"})
      assert_receive {:display_updated, %{id: ^id}}, 500
    end

    test "upsert/1 creates a new display when missing" do
      id = "ups-#{System.unique_integer([:positive])}"
      refute Displays.get(id)
      assert {:ok, d} = Displays.upsert(%{id: id, name: "Y"})
      assert d.id == id
      assert Displays.get(id)
    end

    test "upsert/1 updates an existing display" do
      d = Fixtures.display!("ups2-#{System.unique_integer([:positive])}")
      assert {:ok, updated} = Displays.upsert(%{id: d.id, name: "Renamed"})
      assert updated.name == "Renamed"
    end
  end

  describe "delete/1" do
    test "deletes an existing display and broadcasts" do
      d = Fixtures.display!("del-#{System.unique_integer([:positive])}")
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:#{d.id}")
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "displays")

      assert {:ok, deleted} = Displays.delete(d.id)
      assert deleted.id == d.id
      refute Displays.get(d.id)

      id = d.id
      assert_receive :deleted, 500
      assert_receive {:display_deleted, ^id}, 500
    end

    test "returns :error for unknown id" do
      assert Displays.delete("nope") == :error
    end
  end
end
