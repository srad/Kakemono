defmodule Kakemono.Widgets.InstagramFetchWorkerTest do
  use Kakemono.DataCase, async: false
  use Oban.Testing, repo: Kakemono.Repo

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Instagram, InstagramFetchWorker, InstagramScheduler}
  import Kakemono.Fixtures

  @sample_profile Jason.encode!(%{
                    "data" => %{
                      "user" => %{
                        "edge_owner_to_timeline_media" => %{
                          "edges" => [
                            %{
                              "node" => %{
                                "shortcode" => "AAA",
                                "display_url" => "https://cdn.example.com/1.jpg",
                                "edge_media_to_caption" => %{
                                  "edges" => [%{"node" => %{"text" => "first"}}]
                                }
                              }
                            },
                            %{
                              "node" => %{
                                "shortcode" => "BBB",
                                "display_url" => "https://cdn.example.com/2.jpg",
                                "edge_media_to_caption" => %{"edges" => []}
                              }
                            },
                            %{
                              "node" => %{
                                "shortcode" => "CCC",
                                "display_url" => "https://cdn.example.com/3.jpg"
                              }
                            }
                          ]
                        }
                      }
                    }
                  })

  @sample_graph Jason.encode!(%{
                  "data" => [
                    %{
                      "id" => "1",
                      "media_type" => "IMAGE",
                      "media_url" => "https://cdn.example.com/g1.jpg",
                      "permalink" => "https://www.instagram.com/p/G1/",
                      "caption" => "graph first"
                    },
                    %{
                      "id" => "2",
                      "media_type" => "VIDEO",
                      "media_url" => "https://cdn.example.com/g2.mp4",
                      "thumbnail_url" => "https://cdn.example.com/g2.jpg",
                      "permalink" => "https://www.instagram.com/p/G2/"
                    }
                  ]
                })

  setup do
    Application.put_env(:kakemono, :req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:kakemono, :req_options) end)
    %{scene: scene_fixture()}
  end

  describe "Instagram.parse_profile/1" do
    test "extracts items with src, permalink, caption" do
      items = Instagram.parse_profile(@sample_profile)
      assert length(items) == 3
      first = hd(items)
      assert first["src"] == "https://cdn.example.com/1.jpg"
      assert first["type"] == "image"
      assert first["permalink"] == "https://www.instagram.com/p/AAA/"
      assert first["caption"] == "first"
    end

    test "returns [] for non-JSON input" do
      assert [] = Instagram.parse_profile("not json")
    end

    test "returns [] for unexpected shape" do
      assert [] = Instagram.parse_profile(Jason.encode!(%{"foo" => "bar"}))
    end
  end

  describe "Instagram.parse_graph_media/1" do
    test "extracts API media items" do
      [first, second] = Instagram.parse_graph_media(@sample_graph)
      assert first["src"] == "https://cdn.example.com/g1.jpg"
      assert first["caption"] == "graph first"
      assert first["permalink"] == "https://www.instagram.com/p/G1/"
      assert second["src"] == "https://cdn.example.com/g2.jpg"
    end
  end

  describe "perform/1" do
    test "fetches profile and caches items on the instance", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("instagram", scene.id, %{"username" => "nasa"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_profile)
      end)

      assert :ok = perform_job(InstagramFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert length(updated.config["cached_items"]) == 3
      assert hd(updated.config["cached_items"])["src"] == "https://cdn.example.com/1.jpg"
      refute Map.has_key?(updated.config, "last_error")
      assert is_binary(updated.config["last_fetch_at"])
    end

    test "uses Instagram API media endpoint when access_token is configured", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("instagram", scene.id, %{
          "username" => "nasa",
          "access_token" => "token",
          "max_items" => 1
        })

      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/me/media"
        assert conn.query_string =~ "access_token=token"
        Plug.Conn.send_resp(conn, 200, @sample_graph)
      end)

      assert :ok = perform_job(InstagramFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert [%{"src" => "https://cdn.example.com/g1.jpg"}] = updated.config["cached_items"]
    end

    test "respects max_items config", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("instagram", scene.id, %{"username" => "nasa", "max_items" => 2})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_profile)
      end)

      assert :ok = perform_job(InstagramFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert length(updated.config["cached_items"]) == 2
    end

    test "broadcasts :widget_config_updated on success", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("instagram", scene.id, %{"username" => "nasa"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_profile)
      end)

      Phoenix.PubSub.subscribe(Kakemono.PubSub, "widgets")
      assert :ok = perform_job(InstagramFetchWorker, %{"instance_id" => inst.id})
      iid = inst.id
      assert_receive {:widget_config_updated, %{instance_id: ^iid}}, 500
    end

    test "stores last_error and backs off without retrying on rate limit", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("instagram", scene.id, %{"username" => "nasa"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 429, "rate limited")
      end)

      assert :ok = perform_job(InstagramFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert updated.config["last_error"] == "HTTP 429"
      assert is_binary(updated.config["last_error_at"])

      assert {:ok, next_fetch_at, _offset} =
               DateTime.from_iso8601(updated.config["next_fetch_at"])

      assert DateTime.compare(next_fetch_at, DateTime.utc_now()) == :gt
    end

    test "returns error for retryable server errors", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("instagram", scene.id, %{"username" => "nasa"})

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      assert {:error, {:http_status, 503}} =
               perform_job(InstagramFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert updated.config["last_error"] == "HTTP 503"
      refute Map.has_key?(updated.config, "next_fetch_at")
    end

    test "returns error for non-instagram instance", %{scene: scene} do
      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      assert {:error, {:wrong_type, "clock"}} =
               perform_job(InstagramFetchWorker, %{"instance_id" => clock.id})
    end

    test "no-op for missing instance" do
      assert :ok = perform_job(InstagramFetchWorker, %{"instance_id" => 99_999})
    end
  end

  describe "prefetch/1" do
    test "enqueues when cache is empty", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("instagram", scene.id, %{"username" => "nasa"})

      assert :ok = Kakemono.Widgets.Instagram.prefetch(inst)
      assert_enqueued(worker: InstagramFetchWorker, args: %{instance_id: inst.id})
    end

    test "skips when items are already cached", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("instagram", scene.id, %{
          "username" => "nasa",
          "cached_items" => [%{"src" => "https://x/1.jpg"}]
        })

      assert :ok = Kakemono.Widgets.Instagram.prefetch(inst)
      refute_enqueued(worker: InstagramFetchWorker, args: %{instance_id: inst.id})
    end

    test "skips while rate-limit backoff is active", %{scene: scene} do
      next_fetch_at =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.to_iso8601()

      {:ok, inst} =
        Widgets.create_instance("instagram", scene.id, %{
          "username" => "nasa",
          "next_fetch_at" => next_fetch_at
        })

      assert :ok = Kakemono.Widgets.Instagram.prefetch(inst)
      refute_enqueued(worker: InstagramFetchWorker, args: %{instance_id: inst.id})
    end
  end

  describe "scheduler" do
    test "enqueues one InstagramFetchWorker per instagram instance", %{scene: scene} do
      {:ok, a} = Widgets.create_instance("instagram", scene.id, %{"username" => "a"})
      {:ok, b} = Widgets.create_instance("instagram", scene.id, %{"username" => "b"})
      {:ok, _c} = Widgets.create_instance("clock", scene.id, %{})

      assert {:ok, 2} = perform_job(InstagramScheduler, %{})

      assert_enqueued(worker: InstagramFetchWorker, args: %{instance_id: a.id})
      assert_enqueued(worker: InstagramFetchWorker, args: %{instance_id: b.id})
    end

    test "skips instances with active backoff", %{scene: scene} do
      next_fetch_at =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.to_iso8601()

      {:ok, due} = Widgets.create_instance("instagram", scene.id, %{"username" => "due"})

      {:ok, skipped} =
        Widgets.create_instance("instagram", scene.id, %{
          "username" => "skip",
          "next_fetch_at" => next_fetch_at
        })

      assert {:ok, 1} = perform_job(InstagramScheduler, %{})

      assert_enqueued(worker: InstagramFetchWorker, args: %{instance_id: due.id})
      refute_enqueued(worker: InstagramFetchWorker, args: %{instance_id: skipped.id})
    end
  end
end
