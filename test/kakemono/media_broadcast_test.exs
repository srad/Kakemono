defmodule Kakemono.MediaBroadcastTest do
  use Kakemono.DataCase, async: false

  alias Kakemono.Media
  import Kakemono.Fixtures

  test "Media.update/2 broadcasts {:media_updated, item} on the \"media\" topic" do
    item = media_item_fixture()
    Phoenix.PubSub.subscribe(Kakemono.PubSub, "media")

    {:ok, updated} = Media.update(item, %{status: "ready"})
    iid = updated.id

    assert_receive {:media_updated, %{id: ^iid, status: "ready"}}, 500
  end
end
