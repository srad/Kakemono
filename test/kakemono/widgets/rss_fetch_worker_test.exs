defmodule Kakemono.Widgets.RssFetchWorkerTest do
  use Kakemono.DataCase, async: false
  use Oban.Testing, repo: Kakemono.Repo

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Rss, RssFetchWorker, RssScheduler}
  import Kakemono.Fixtures

  @sample_rss """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0">
    <channel>
      <title>Test Feed</title>
      <item><title>Item One</title><link>http://example.com/1</link><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate></item>
      <item><title>Item Two</title><link>http://example.com/2</link><pubDate>Tue, 02 Jan 2024 00:00:00 GMT</pubDate></item>
      <item><title>Item Three</title><link>http://example.com/3</link></item>
    </channel>
  </rss>
  """

  setup do
    Application.put_env(:kakemono, :req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:kakemono, :req_options) end)
    %{scene: scene_fixture()}
  end

  describe "Rss.parse_feed/1" do
    test "parses items from valid RSS" do
      {title, items} = Rss.parse_feed(@sample_rss)
      assert title == "Test Feed"
      assert length(items) == 3
      assert hd(items)["title"] == "Item One"
      assert hd(items)["link"] == "http://example.com/1"
    end

    test "returns empty list for invalid XML" do
      assert {"", []} = Rss.parse_feed("not xml")
    end
  end

  describe "perform/1" do
    test "fetches RSS and caches items on the instance", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{"url" => "http://example.com/feed"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_rss)
      end)

      assert :ok = perform_job(RssFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert updated.config["feed_title"] == "Test Feed"
      assert length(updated.config["cached_items"]) == 3
      assert hd(updated.config["cached_items"])["title"] == "Item One"
    end

    test "respects max_items config", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{
          "url" => "http://example.com/feed",
          "max_items" => 2
        })

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_rss)
      end)

      assert :ok = perform_job(RssFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert length(updated.config["cached_items"]) == 2
    end

    test "broadcasts :widget_config_updated on success", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{"url" => "http://example.com/feed"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_rss)
      end)

      Phoenix.PubSub.subscribe(Kakemono.PubSub, "widgets")
      assert :ok = perform_job(RssFetchWorker, %{"instance_id" => inst.id})
      iid = inst.id
      assert_receive {:widget_config_updated, %{instance_id: ^iid}}, 500
    end

    test "returns error for non-rss instance", %{scene: scene} do
      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      assert {:error, {:wrong_type, "clock"}} =
               perform_job(RssFetchWorker, %{"instance_id" => clock.id})
    end

    test "no-op for missing instance" do
      assert :ok = perform_job(RssFetchWorker, %{"instance_id" => 99999})
    end
  end

  describe "prefetch/1" do
    test "enqueues when cache is empty", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{"url" => "http://example.com/feed"})

      assert :ok = Kakemono.Widgets.Rss.prefetch(inst)
      assert_enqueued(worker: RssFetchWorker, args: %{instance_id: inst.id})
    end

    test "skips when items are already cached", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{
          "url" => "http://example.com/feed",
          "cached_items" => [%{"title" => "x"}]
        })

      assert :ok = Kakemono.Widgets.Rss.prefetch(inst)
      refute_enqueued(worker: RssFetchWorker, args: %{instance_id: inst.id})
    end
  end

  describe "scheduler" do
    test "enqueues one RssFetchWorker per rss instance", %{scene: scene} do
      {:ok, r1} = Widgets.create_instance("rss", scene.id, %{"url" => "http://a.com/feed"})
      {:ok, r2} = Widgets.create_instance("rss", scene.id, %{"url" => "http://b.com/feed"})
      {:ok, _c} = Widgets.create_instance("clock", scene.id, %{})

      assert {:ok, 2} = perform_job(RssScheduler, %{})

      assert_enqueued(worker: RssFetchWorker, args: %{instance_id: r1.id})
      assert_enqueued(worker: RssFetchWorker, args: %{instance_id: r2.id})
    end
  end
end
