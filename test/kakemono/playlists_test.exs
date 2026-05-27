defmodule Kakemono.PlaylistsTest do
  use Kakemono.DataCase, async: false

  alias Kakemono.Playlists
  alias Kakemono.Playlists.Entry
  alias Kakemono.Repo
  import Kakemono.Fixtures

  setup do
    display_fixture(id: "tablet")
    :ok
  end

  test "create/1 persists a playlist" do
    {:ok, p} = Playlists.create(%{name: "My PL"})
    assert p.id
    assert p.name == "My PL"
  end

  test "create/1 requires name" do
    assert {:error, changeset} = Playlists.create(%{})
    refute changeset.valid?
  end

  test "add_item/2 assigns sequential order_index starting from 0" do
    p = playlist_fixture()
    i1 = media_item_fixture()
    i2 = media_item_fixture()
    i3 = media_item_fixture()

    {:ok, _} = Playlists.add_item(p, i1.id)
    {:ok, _} = Playlists.add_item(p, i2.id)
    {:ok, _} = Playlists.add_item(p, i3.id)

    indexes = Repo.all(Entry) |> Enum.sort_by(& &1.id) |> Enum.map(& &1.order_index)
    assert indexes == [0, 1, 2]
  end

  test "get_with_items/1 returns entries with preloaded media, in order" do
    p = playlist_fixture()
    i1 = media_item_fixture()
    i2 = media_item_fixture()
    {:ok, _} = Playlists.add_item(p, i1.id)
    {:ok, _} = Playlists.add_item(p, i2.id)

    loaded = Playlists.get_with_items(p.id)
    assert [e1, e2] = loaded.entries
    assert e1.media_item_id == i1.id
    assert e2.media_item_id == i2.id
    assert %Kakemono.Media.Item{} = e1.media_item
  end

  test "reorder/2 rewrites order_index without violating unique index" do
    p = playlist_fixture()
    i1 = media_item_fixture()
    i2 = media_item_fixture()
    i3 = media_item_fixture()
    {:ok, e1} = Playlists.add_item(p, i1.id)
    {:ok, e2} = Playlists.add_item(p, i2.id)
    {:ok, e3} = Playlists.add_item(p, i3.id)

    :ok = Playlists.reorder(p.id, [e3.id, e1.id, e2.id])

    after_entries = Playlists.get_with_items(p.id).entries
    assert Enum.map(after_entries, & &1.id) == [e3.id, e1.id, e2.id]
    assert Enum.map(after_entries, & &1.order_index) == [0, 1, 2]
  end

  test "remove_entry/1 deletes the entry and compacts indexes" do
    p = playlist_fixture()
    [i1, i2, i3] = for _ <- 1..3, do: media_item_fixture()
    {:ok, _} = Playlists.add_item(p, i1.id)
    {:ok, e2} = Playlists.add_item(p, i2.id)
    {:ok, _} = Playlists.add_item(p, i3.id)

    :ok = Playlists.remove_entry(e2.id)

    remaining = Playlists.get_with_items(p.id).entries
    assert length(remaining) == 2
    assert Enum.map(remaining, & &1.order_index) == [0, 1]
  end

  test "reorder/2 broadcasts :playlist_updated to display topic" do
    Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:tablet")
    p = playlist_fixture()
    i1 = media_item_fixture()
    i2 = media_item_fixture()
    {:ok, e1} = Playlists.add_item(p, i1.id)
    {:ok, e2} = Playlists.add_item(p, i2.id)

    # Drain the broadcasts from add_item
    flush_mailbox()

    :ok = Playlists.reorder(p.id, [e2.id, e1.id])
    assert_receive {:playlist_updated, %{playlist_id: pid}}, 500
    assert pid == p.id
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      50 -> :ok
    end
  end

  describe "update_settings/2" do
    test "updates fit_mode and broadcasts" do
      d = Kakemono.Fixtures.display!("ds-#{System.unique_integer([:positive])}")
      pl = Kakemono.Fixtures.playlist_fixture()
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:#{d.id}")

      assert {:ok, updated} = Kakemono.Playlists.update_settings(pl, %{fit_mode: "cover"})
      assert updated.fit_mode == "cover"
      assert_receive {:playlist_updated, %{playlist_id: pid}}, 500
      assert pid == pl.id
    end

    test "rejects invalid fit_mode" do
      pl = Kakemono.Fixtures.playlist_fixture()
      assert {:error, cs} = Kakemono.Playlists.update_settings(pl, %{fit_mode: "bogus"})
      refute cs.valid?
    end

    test "playlist default fit_mode is contain" do
      pl = Kakemono.Fixtures.playlist_fixture()
      assert pl.fit_mode == "contain"
    end

    test "updates transition_duration_ms and broadcasts" do
      d = Kakemono.Fixtures.display!("ds-td-#{System.unique_integer([:positive])}")
      pl = Kakemono.Fixtures.playlist_fixture()
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "display:#{d.id}")

      assert {:ok, updated} =
               Kakemono.Playlists.update_settings(pl, %{transition_duration_ms: 12_000})

      assert updated.transition_duration_ms == 12_000
      assert_receive {:playlist_updated, %{playlist_id: pid}}, 500
      assert pid == pl.id
    end

    test "clears transition_duration_ms when nil is passed" do
      pl = Kakemono.Fixtures.playlist_fixture()
      {:ok, pl} = Kakemono.Playlists.update_settings(pl, %{transition_duration_ms: 8000})
      assert pl.transition_duration_ms == 8000

      assert {:ok, cleared} =
               Kakemono.Playlists.update_settings(pl, %{transition_duration_ms: nil})

      assert cleared.transition_duration_ms == nil
    end

    test "rejects transition_duration_ms below 500" do
      pl = Kakemono.Fixtures.playlist_fixture()

      assert {:error, cs} =
               Kakemono.Playlists.update_settings(pl, %{transition_duration_ms: 100})

      refute cs.valid?
    end

    test "rejects transition_duration_ms above 600_000" do
      pl = Kakemono.Fixtures.playlist_fixture()

      assert {:error, cs} =
               Kakemono.Playlists.update_settings(pl, %{transition_duration_ms: 1_000_000})

      refute cs.valid?
    end

    test "playlist default transition_duration_ms is nil" do
      pl = Kakemono.Fixtures.playlist_fixture()
      assert pl.transition_duration_ms == nil
    end
  end
end
