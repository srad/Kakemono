defmodule Kakemono.Widgets.WeatherTest do
  # async: false — the fetch/1 dispatch tests mutate the global :req_options env.
  use ExUnit.Case, async: false
  alias Kakemono.Widgets.Weather
  alias Kakemono.Widgets.Instance

  describe "fetch/1 source dispatch" do
    setup do
      Application.put_env(:kakemono, :req_options, plug: {Req.Test, __MODULE__})
      on_exit(fn -> Application.delete_env(:kakemono, :req_options) end)
      :ok
    end

    defp instance(source) do
      %Instance{config: %{"latitude" => 52.5, "longitude" => 13.4, "source" => source}}
    end

    test "routes to Open-Meteo by default and wraps the body under \"cached\"" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "api.open-meteo.com"
        Req.Test.json(conn, %{"current" => %{"temperature_2m" => 1.0}})
      end)

      assert {:ok, %{"cached" => %{"current" => %{"temperature_2m" => 1.0}}}} =
               Weather.fetch(instance(nil))
    end

    test "routes to MET Norway when source is met_no" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "api.met.no"
        Req.Test.json(conn, %{"properties" => %{"timeseries" => []}})
      end)

      assert {:ok, %{"cached" => %{"hourly" => _}}} = Weather.fetch(instance("met_no"))
    end

    test "routes to Bright Sky when source is bright_sky" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "api.brightsky.dev"

        if String.contains?(conn.request_path, "current_weather") do
          Req.Test.json(conn, %{"weather" => %{"timestamp" => "2026-05-28T12:00:00Z"}})
        else
          Req.Test.json(conn, %{"weather" => []})
        end
      end)

      assert {:ok, %{"cached" => %{"current" => _}}} = Weather.fetch(instance("bright_sky"))
    end
  end

  describe "is_day_for/4 (pure)" do
    setup do
      {:ok, sunrise} = DateTime.new(~D[2026-05-22], ~T[05:00:00], "Etc/UTC")
      {:ok, sunset} = DateTime.new(~D[2026-05-22], ~T[20:00:00], "Etc/UTC")
      %{sunrise: sunrise, sunset: sunset}
    end

    test "returns true at sunrise (inclusive)", %{sunrise: sr, sunset: ss} do
      assert Weather.is_day_for(sr, sr, ss, false)
    end

    test "returns true at midday", %{sunrise: sr, sunset: ss} do
      {:ok, noon} = DateTime.new(~D[2026-05-22], ~T[12:00:00], "Etc/UTC")
      assert Weather.is_day_for(noon, sr, ss, false)
    end

    test "returns false at sunset (exclusive)", %{sunrise: sr, sunset: ss} do
      refute Weather.is_day_for(ss, sr, ss, true)
    end

    test "returns false at night", %{sunrise: sr, sunset: ss} do
      {:ok, midnight} = DateTime.new(~D[2026-05-22], ~T[23:30:00], "Etc/UTC")
      refute Weather.is_day_for(midnight, sr, ss, true)
    end

    test "uses fallback when sunrise is nil" do
      {:ok, ss} = DateTime.new(~D[2026-05-22], ~T[20:00:00], "Etc/UTC")
      {:ok, noon} = DateTime.new(~D[2026-05-22], ~T[12:00:00], "Etc/UTC")
      assert Weather.is_day_for(noon, nil, ss, true)
      refute Weather.is_day_for(noon, nil, ss, false)
    end
  end

  describe "compute_is_day/1" do
    test "derives day from sunrise/sunset of cached daily payload" do
      now = DateTime.utc_now()
      offset = 0
      one_hour_ago = DateTime.add(now, -3600, :second)
      one_hour_ahead = DateTime.add(now, 3600, :second)

      cached = %{
        "utc_offset_seconds" => offset,
        "daily" => %{
          "sunrise" => [iso_local(one_hour_ago)],
          "sunset" => [iso_local(one_hour_ahead)]
        },
        "current" => %{"is_day" => 0}
      }

      # Wall-clock is between the two: it's daytime, regardless of the stale
      # snapshot saying is_day=0.
      assert Weather.compute_is_day(cached) == true
    end

    test "falls back to current.is_day when daily is missing" do
      cached = %{
        "utc_offset_seconds" => 0,
        "current" => %{"is_day" => 0}
      }

      assert Weather.compute_is_day(cached) == false
    end
  end

  defp iso_local(dt) do
    "#{Date.to_iso8601(DateTime.to_date(dt))}T#{Time.to_iso8601(DateTime.to_time(dt)) |> String.slice(0, 5)}"
  end
end
