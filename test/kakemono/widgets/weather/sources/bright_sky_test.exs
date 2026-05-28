defmodule Kakemono.Widgets.Weather.Sources.BrightSkyTest do
  use ExUnit.Case, async: true

  alias Kakemono.Widgets.Weather.Sources.BrightSky

  defp current_fixture do
    %{
      "weather" => %{
        "timestamp" => "2026-05-28T12:00:00+02:00",
        "temperature" => 18.5,
        "relative_humidity" => 55,
        "wind_speed" => 12.0,
        "icon" => "partly-cloudy-day"
      }
    }
  end

  defp range_fixture do
    %{
      "weather" => [
        record("2026-05-28T12:00:00+02:00", 18.5, "partly-cloudy-day"),
        record("2026-05-28T13:00:00+02:00", 19.0, "rain"),
        record("2026-05-28T23:00:00+02:00", 11.0, "clear-night"),
        record("2026-05-29T12:00:00+02:00", 15.0, "thunderstorm"),
        record("2026-05-30T12:00:00+02:00", 4.0, "snow")
      ]
    }
  end

  defp record(ts, temp, icon) do
    %{"timestamp" => ts, "temperature" => temp, "icon" => icon}
  end

  describe "normalize/2" do
    test "maps current conditions and day/night from icon suffix" do
      norm = BrightSky.normalize(current_fixture(), range_fixture())
      current = norm["current"]

      assert current["time"] == "2026-05-28T12:00:00+02:00"
      assert current["temperature_2m"] == 18.5
      assert current["relative_humidity_2m"] == 55
      assert current["wind_speed_10m"] == 12.0
      # partly-cloudy-day -> WMO 1, day
      assert current["weather_code"] == 1
      assert current["is_day"] == 1
    end

    test "parses utc offset from the timestamp" do
      norm = BrightSky.normalize(current_fixture(), range_fixture())
      assert norm["utc_offset_seconds"] == 7200
    end

    test "hourly carries codes and is_day, incl. night record" do
      hourly = BrightSky.normalize(current_fixture(), range_fixture())["hourly"]

      assert hd(hourly["temperature_2m"]) == 18.5
      # rain -> 61, thunderstorm -> 95, snow -> 71
      assert Enum.at(hourly["weather_code"], 1) == 61
      assert Enum.at(hourly["weather_code"], 3) == 95
      assert Enum.at(hourly["weather_code"], 4) == 71
      # clear-night -> is_day 0
      assert Enum.at(hourly["is_day"], 2) == 0
    end

    test "daily aggregates per-date max/min and a midday code" do
      daily = BrightSky.normalize(current_fixture(), range_fixture())["daily"]

      assert daily["time"] == ["2026-05-28", "2026-05-29", "2026-05-30"]
      assert daily["temperature_2m_max"] == [19.0, 15.0, 4.0]
      assert daily["temperature_2m_min"] == [11.0, 15.0, 4.0]
    end
  end

  describe "fetch/3" do
    test "combines current_weather and weather range into a normalized map" do
      Req.Test.stub(__MODULE__, fn conn ->
        cond do
          String.contains?(conn.request_path, "current_weather") ->
            Req.Test.json(conn, current_fixture())

          true ->
            Req.Test.json(conn, range_fixture())
        end
      end)

      opts = [req_options: [plug: {Req.Test, __MODULE__}]]
      assert {:ok, norm} = BrightSky.fetch(52.5, 13.4, opts)
      assert norm["current"]["temperature_2m"] == 18.5
      assert length(norm["hourly"]["time"]) == 5
    end
  end
end
