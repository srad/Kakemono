defmodule Kakemono.Widgets.RssFetchWorkerTest do
  use Kakemono.DataCase, async: false
  use Oban.Testing, repo: Kakemono.Repo, engine: Oban.Engines.Lite, notifier: Oban.Notifiers.PG

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{FetchWorker, RefreshScheduler, Rss}
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

  @sample_rss_091 """
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE rss PUBLIC "-//Netscape Communications//DTD RSS 0.91//EN"
    "http://my.netscape.com/publish/formats/rss-0.91.dtd">
  <rss version="0.91">
    <channel>
      <title>BBC News | World Edition</title>
      <link>http://news.bbc.co.uk/</link>
      <description>BBC News headlines</description>
      <item>
        <title>BBC News | Africa | World Edition</title>
        <link>http://newsrss.bbc.co.uk/rss/newsonline_world_edition/africa/rss.xml</link>
        <description>Africa headlines</description>
      </item>
      <item>
        <title>BBC News | Americas | World Edition</title>
        <link>http://newsrss.bbc.co.uk/rss/newsonline_world_edition/americas/rss.xml</link>
      </item>
    </channel>
  </rss>
  """

  @sample_atom """
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom">
    <title>Atom Feed</title>
    <entry>
      <title>Atom Item</title>
      <link href="http://example.com/atom-1" />
      <updated>2024-03-01T12:00:00Z</updated>
    </entry>
  </feed>
  """

  @sample_rdf_rss """
  <?xml version="1.0" encoding="UTF-8"?>
  <rdf:RDF
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel rdf:about="http://example.com/rdf">
      <title>RDF Feed</title>
      <link>http://example.com/rdf</link>
    </channel>
    <item rdf:about="http://example.com/rdf-1">
      <title>RDF Item</title>
      <link>http://example.com/rdf-1</link>
      <dc:date>2024-04-01T00:00:00Z</dc:date>
    </item>
  </rdf:RDF>
  """

  @sample_opml """
  <?xml version="1.0" encoding="UTF-8"?>
  <opml version="1.1">
    <head>
      <title>BBC News Website UK Edition RSS Feeds</title>
    </head>
    <body>
      <outline
        text="BBC News | Africa | World Edition"
        title="BBC News | Africa | World Edition"
        xmlUrl="http://newsrss.bbc.co.uk/rss/newsonline_world_edition/africa/rss.xml"
        type="rss"
        htmlUrl="http://news.bbc.co.uk/go/rss/-/2/hi/africa/default.stm" />
      <outline
        text="BBC News | Americas | World Edition"
        xmlUrl="http://newsrss.bbc.co.uk/rss/newsonline_world_edition/americas/rss.xml"
        type="rss" />
    </body>
  </opml>
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

    test "parses items from RSS 0.91 with a doctype" do
      {title, items} = Rss.parse_feed(@sample_rss_091)
      assert title == "BBC News | World Edition"
      assert length(items) == 2
      assert hd(items)["title"] == "BBC News | Africa | World Edition"

      assert hd(items)["link"] ==
               "http://newsrss.bbc.co.uk/rss/newsonline_world_edition/africa/rss.xml"

      assert hd(items)["pub_date"] == ""
    end

    test "parses namespaced Atom feeds" do
      {title, items} = Rss.parse_feed(@sample_atom)
      assert title == "Atom Feed"
      assert length(items) == 1
      assert hd(items)["title"] == "Atom Item"
      assert hd(items)["link"] == "http://example.com/atom-1"
      assert hd(items)["pub_date"] == "2024-03-01T12:00:00Z"
    end

    test "parses RDF RSS feeds" do
      {title, items} = Rss.parse_feed(@sample_rdf_rss)
      assert title == "RDF Feed"
      assert length(items) == 1
      assert hd(items)["title"] == "RDF Item"
      assert hd(items)["link"] == "http://example.com/rdf-1"
      assert hd(items)["pub_date"] == "2024-04-01T00:00:00Z"
    end

    test "parses OPML directories as feed lists" do
      {title, items} = Rss.parse_feed(@sample_opml)
      assert title == "BBC News Website UK Edition RSS Feeds"
      assert length(items) == 2

      assert hd(items)["title"] == "BBC News | Africa | World Edition"
      assert hd(items)["link"] == "http://news.bbc.co.uk/go/rss/-/2/hi/africa/default.stm"
      assert hd(items)["pub_date"] == ""

      assert List.last(items)["title"] == "BBC News | Americas | World Edition"

      assert List.last(items)["link"] ==
               "http://newsrss.bbc.co.uk/rss/newsonline_world_edition/americas/rss.xml"
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

      assert :ok = perform_job(FetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert updated.config["feed_title"] == "Test Feed"
      assert length(updated.config["cached_items"]) == 3
      assert hd(updated.config["cached_items"])["title"] == "Item One"
    end

    test "fetches RSS 0.91 and caches items on the instance", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{"url" => "http://example.com/rss091"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_rss_091)
      end)

      assert :ok = perform_job(FetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert updated.config["feed_title"] == "BBC News | World Edition"
      assert length(updated.config["cached_items"]) == 2
      assert hd(updated.config["cached_items"])["title"] == "BBC News | Africa | World Edition"
    end

    test "fetches OPML and caches feed directory entries on the instance", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{"url" => "http://example.com/feeds.opml"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_opml)
      end)

      assert :ok = perform_job(FetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert updated.config["feed_title"] == "BBC News Website UK Edition RSS Feeds"
      assert length(updated.config["cached_items"]) == 2
      assert hd(updated.config["cached_items"])["title"] == "BBC News | Africa | World Edition"
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

      assert :ok = perform_job(FetchWorker, %{"instance_id" => inst.id})

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
      assert :ok = perform_job(FetchWorker, %{"instance_id" => inst.id})
      iid = inst.id
      assert_receive {:widget_config_updated, %{instance_id: ^iid}}, 500
    end

    test "no-op for a non-fetching widget instance", %{scene: scene} do
      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      assert :ok = perform_job(FetchWorker, %{"instance_id" => clock.id})
    end

    test "no-op for missing instance" do
      assert :ok = perform_job(FetchWorker, %{"instance_id" => 99999})
    end
  end

  describe "prefetch/1" do
    test "enqueues when cache is empty", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{"url" => "http://example.com/feed"})

      assert :ok = Kakemono.Widgets.Rss.prefetch(inst)
      assert_enqueued(worker: FetchWorker, args: %{instance_id: inst.id})
    end

    test "skips when items are already cached", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{
          "url" => "http://example.com/feed",
          "cached_items" => [%{"title" => "x"}],
          "fetched_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
        })

      assert :ok = Kakemono.Widgets.Rss.prefetch(inst)
      refute_enqueued(worker: FetchWorker, args: %{instance_id: inst.id})
    end
  end

  describe "update_config/2" do
    test "changing the URL clears stale cache, broadcasts, and forces a refresh", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("rss", scene.id, %{
          "url" => "http://example.com/old",
          "cached_items" => [
            %{"title" => "Old", "link" => "http://example.com/old", "pub_date" => ""}
          ],
          "feed_title" => "Old Feed",
          "fetched_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
        })

      %{instance_id: inst.id} |> FetchWorker.new() |> Oban.insert!()
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "widgets")

      assert {:ok, updated} = Widgets.update_config(inst, %{"url" => "http://example.com/new"})

      refute Map.has_key?(updated.config, "cached_items")
      refute Map.has_key?(updated.config, "feed_title")
      refute Map.has_key?(updated.config, "fetched_at")
      assert_receive {:widget_config_updated, %{instance_id: instance_id}}, 500
      assert instance_id == inst.id

      jobs = all_enqueued(worker: FetchWorker)
      assert Enum.count(jobs, &(&1.args["instance_id"] == inst.id)) == 2
    end
  end

  describe "scheduler" do
    test "enqueues one FetchWorker per instance of the given types", %{scene: scene} do
      {:ok, r1} = Widgets.create_instance("rss", scene.id, %{"url" => "http://a.com/feed"})
      {:ok, r2} = Widgets.create_instance("rss", scene.id, %{"url" => "http://b.com/feed"})
      {:ok, _c} = Widgets.create_instance("clock", scene.id, %{})

      assert {:ok, 2} =
               perform_job(RefreshScheduler, %{"types" => ["weather", "air_quality", "rss"]})

      assert_enqueued(worker: FetchWorker, args: %{instance_id: r1.id})
      assert_enqueued(worker: FetchWorker, args: %{instance_id: r2.id})
    end
  end
end
