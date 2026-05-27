defmodule Kakemono.Widgets.WeatherFetchWorkerTest do
  use Kakemono.DataCase, async: false
  use Oban.Testing, repo: Kakemono.Repo

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{WeatherFetchWorker, WeatherScheduler}
  import Kakemono.Fixtures

  setup do
    Application.put_env(:kakemono, :req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:kakemono, :req_options) end)
    %{scene: scene_fixture()}
  end

  describe "perform/1" do
    test "fetches Open-Meteo data and caches it on the instance", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("weather", scene.id, %{"latitude" => 52.5, "longitude" => 13.4})

      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.query_string =~ "hourly="
        assert conn.query_string =~ "daily="
        assert conn.query_string =~ "forecast_days=7"

        Req.Test.json(conn, %{
          "current" => %{
            "time" => "2026-05-22T12:00",
            "temperature_2m" => 18.5,
            "weather_code" => 0,
            "is_day" => 1
          },
          "hourly" => %{
            "time" => ["2026-05-22T12:00", "2026-05-22T13:00"],
            "temperature_2m" => [18.5, 19.0],
            "weather_code" => [0, 1],
            "is_day" => [1, 1]
          },
          "daily" => %{
            "time" => ["2026-05-22", "2026-05-23"],
            "weather_code" => [0, 3],
            "temperature_2m_max" => [22.0, 18.0],
            "temperature_2m_min" => [12.0, 10.0],
            "sunrise" => ["2026-05-22T05:30", "2026-05-23T05:29"],
            "sunset" => ["2026-05-22T20:45", "2026-05-23T20:46"]
          }
        })
      end)

      assert :ok = perform_job(WeatherFetchWorker, %{"instance_id" => inst.id})

      updated = Widgets.get_instance(inst.id)
      assert updated.config["cached"]["current"]["temperature_2m"] == 18.5
      assert updated.config["cached"]["hourly"]["temperature_2m"] == [18.5, 19.0]
      assert updated.config["cached"]["daily"]["temperature_2m_max"] == [22.0, 18.0]
    end

    test "broadcasts :widget_config_updated on success", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("weather", scene.id, %{"latitude" => 0.0, "longitude" => 0.0})

      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"current" => %{"temperature_2m" => 1.0}})
      end)

      Phoenix.PubSub.subscribe(Kakemono.PubSub, "widgets")
      assert :ok = perform_job(WeatherFetchWorker, %{"instance_id" => inst.id})
      iid = inst.id
      assert_receive {:widget_config_updated, %{instance_id: ^iid}}, 500
    end

    test "returns error for non-weather instance", %{scene: scene} do
      {:ok, clock} = Widgets.create_instance("clock", scene.id, %{})

      assert {:error, {:wrong_type, "clock"}} =
               perform_job(WeatherFetchWorker, %{"instance_id" => clock.id})
    end

    test "no-op for missing instance" do
      assert :ok = perform_job(WeatherFetchWorker, %{"instance_id" => 99999})
    end
  end

  describe "prefetch/1" do
    test "enqueues a fetch when cache is empty and a location is set", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("weather", scene.id, %{"latitude" => 48.1, "longitude" => 11.5})

      assert :ok = Kakemono.Widgets.Weather.prefetch(inst)
      assert_enqueued(worker: WeatherFetchWorker, args: %{instance_id: inst.id})
    end

    test "skips when cache is already populated", %{scene: scene} do
      {:ok, inst} =
        Widgets.create_instance("weather", scene.id, %{
          "latitude" => 48.1,
          "longitude" => 11.5,
          "cached" => %{"current" => %{"temperature_2m" => 20.0}}
        })

      assert :ok = Kakemono.Widgets.Weather.prefetch(inst)
      refute_enqueued(worker: WeatherFetchWorker, args: %{instance_id: inst.id})
    end

    test "skips when location is unconfigured (0.0/0.0)", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("weather", scene.id, %{})

      assert :ok = Kakemono.Widgets.Weather.prefetch(inst)
      refute_enqueued(worker: WeatherFetchWorker, args: %{instance_id: inst.id})
    end
  end

  describe "scheduler" do
    test "enqueues one WeatherFetchWorker per weather instance", %{scene: scene} do
      {:ok, w1} =
        Widgets.create_instance("weather", scene.id, %{"latitude" => 1.0, "longitude" => 2.0})

      {:ok, w2} =
        Widgets.create_instance("weather", scene.id, %{"latitude" => 3.0, "longitude" => 4.0})

      {:ok, _c} = Widgets.create_instance("clock", scene.id, %{})

      assert {:ok, 2} = perform_job(WeatherScheduler, %{})

      assert_enqueued(worker: WeatherFetchWorker, args: %{instance_id: w1.id})
      assert_enqueued(worker: WeatherFetchWorker, args: %{instance_id: w2.id})
    end
  end
end
