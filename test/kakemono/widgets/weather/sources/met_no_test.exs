defmodule Kakemono.Widgets.Weather.Sources.MetNoTest do
  use ExUnit.Case, async: true

  alias Kakemono.Widgets.Weather.Sources.MetNo

  defp series_entry(time, temp, symbol, precip_prob \\ nil) do
    %{
      "time" => time,
      "data" => %{
        "instant" => %{
          "details" => %{
            "air_temperature" => temp,
            "relative_humidity" => 60.0,
            "wind_speed" => 5.0
          }
        },
        "next_1_hours" => %{
          "summary" => %{"symbol_code" => symbol},
          "details" => %{"probability_of_precipitation" => precip_prob}
        }
      }
    }
  end

  defp fixture do
    %{
      "properties" => %{
        "timeseries" => [
          series_entry("2026-05-28T12:00:00Z", 18.0, "clearsky_day", 10),
          series_entry("2026-05-28T13:00:00Z", 19.0, "partlycloudy_day", 40),
          series_entry("2026-05-28T23:00:00Z", 12.0, "partlycloudy_night", 20),
          series_entry("2026-05-29T12:00:00Z", 16.0, "lightrain", 70),
          series_entry("2026-05-29T18:00:00Z", 14.0, "rainshowers_day", 55),
          series_entry("2026-05-30T12:00:00Z", 5.0, "snow", 90)
        ]
      }
    }
  end

  describe "normalize/1" do
    test "maps current conditions, day/night and unit conversion" do
      norm = MetNo.normalize(fixture())
      current = norm["current"]

      assert current["time"] == "2026-05-28T12:00:00Z"
      assert current["temperature_2m"] == 18.0
      assert current["relative_humidity_2m"] == 60.0
      # 5 m/s -> 18.0 km/h
      assert current["wind_speed_10m"] == 18.0
      # clearsky_day -> WMO 0
      assert current["weather_code"] == 0
      assert current["is_day"] == 1
    end

    test "night symbol yields is_day 0" do
      norm = MetNo.normalize(fixture())
      # third hourly entry is partlycloudy_night
      assert Enum.at(norm["hourly"]["is_day"], 2) == 0
      assert Enum.at(norm["hourly"]["weather_code"], 2) == 1
    end

    test "hourly carries times, temps and synthetic codes" do
      hourly = MetNo.normalize(fixture())["hourly"]

      assert hd(hourly["time"]) == "2026-05-28T12:00:00Z"
      assert hd(hourly["temperature_2m"]) == 18.0
      # lightrain -> rain (61), snow -> 71
      assert Enum.at(hourly["weather_code"], 3) == 61
      assert Enum.at(hourly["weather_code"], 5) == 71
    end

    test "daily aggregates per-date max/min and a midday code" do
      daily = MetNo.normalize(fixture())["daily"]

      assert daily["time"] == ["2026-05-28", "2026-05-29", "2026-05-30"]
      assert daily["temperature_2m_max"] == [19.0, 16.0, 5.0]
      assert daily["temperature_2m_min"] == [12.0, 14.0, 5.0]
      # day 1 midday closest entry is clearsky_day (12:00) -> 0
      assert hd(daily["weather_code"]) == 0
    end

    test "daily carries the max probability_of_precipitation per day" do
      daily = MetNo.normalize(fixture())["daily"]

      assert daily["precipitation_probability_max"] == [40, 70, 90]
    end

    test "daily precipitation probability is nil-safe when the feed omits it" do
      body = %{
        "properties" => %{
          "timeseries" => [series_entry("2026-05-28T12:00:00Z", 18.0, "clearsky_day")]
        }
      }

      daily = MetNo.normalize(body)["daily"]
      assert daily["precipitation_probability_max"] == [nil]
    end

    test "omits utc_offset_seconds and sunrise/sunset" do
      norm = MetNo.normalize(fixture())
      refute Map.has_key?(norm, "utc_offset_seconds")
      refute Map.has_key?(norm["daily"], "sunrise")
    end
  end

  describe "fetch/3" do
    setup do
      Application.put_env(:kakemono, :met_no_user_agent, "TestAgent/9.9 (test)")
      on_exit(fn -> Application.delete_env(:kakemono, :met_no_user_agent) end)
    end

    test "sends the configured User-Agent and returns a normalized map" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "user-agent") == ["TestAgent/9.9 (test)"]
        Req.Test.json(conn, fixture())
      end)

      opts = [req_options: [plug: {Req.Test, __MODULE__}]]
      assert {:ok, norm} = MetNo.fetch(59.9, 10.7, opts)
      assert norm["current"]["temperature_2m"] == 18.0
    end
  end
end
