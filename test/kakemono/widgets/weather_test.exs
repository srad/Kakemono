defmodule Kakemono.Widgets.WeatherTest do
  use ExUnit.Case, async: true
  alias Kakemono.Widgets.Weather

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
