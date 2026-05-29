defmodule Kakemono.Widgets.WeatherTest do
  # async: false — the fetch/1 dispatch tests mutate the global :req_options env.
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
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

  describe "merge_config/2" do
    test "retains cached data when the source changes (widget never blanks on switch)" do
      old = %{
        "source" => "open_meteo",
        "latitude" => 52.5,
        "longitude" => 13.4,
        "cached" => %{"current" => %{"temperature_2m" => 1.0}}
      }

      merged = Weather.merge_config(old, %{"source" => "met_no"})

      assert merged["source"] == "met_no"
      assert merged["cached"] == %{"current" => %{"temperature_2m" => 1.0}}
    end

    test "retains cached data when coordinates change" do
      old = %{"latitude" => 52.5, "longitude" => 13.4, "cached" => %{"current" => %{}}}

      merged = Weather.merge_config(old, %{"latitude" => 48.1, "longitude" => 11.6})

      assert merged["latitude"] == 48.1
      assert merged["cached"] == %{"current" => %{}}
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

  describe "render/1" do
    test "includes the sky art layer behind weather content" do
      html =
        render_component(&Weather.render/1,
          instance: %Instance{
            id: 123,
            config: %{
              "label" => "Berlin",
              "latitude" => 52.52,
              "longitude" => 13.405,
              "timezone" => "Europe/Berlin",
              "cached" => %{
                "utc_offset_seconds" => 7200,
                "current" => %{"temperature_2m" => 21.0, "weather_code" => 0, "is_day" => 1}
              }
            }
          }
        )

      assert html =~ ~s(class="kw-w-sky")
      assert html =~ ~s(class="kw-w-stars")
      assert html =~ ~s(class="kw-w-sun-body")
      assert html =~ ~s(class="kw-w-moon-body")
      assert html =~ "kw-w-content"
    end

    test "renders roomy forecast as a visual day-by-hour table" do
      dates = ["2026-05-29", "2026-05-30", "2026-05-31", "2026-06-01"]
      hours = [6, 12, 18, 21]

      times =
        for date <- dates, hour <- hours do
          "#{date}T#{String.pad_leading(Integer.to_string(hour), 2, "0")}:00"
        end

      html =
        render_component(&Weather.render/1,
          instance: %Instance{
            id: 124,
            config: %{
              "label" => "Berlin",
              "cached" => %{
                "current" => %{"temperature_2m" => 21.0, "weather_code" => 0, "is_day" => 1},
                "hourly" => %{
                  "time" => times,
                  "temperature_2m" => Enum.to_list(18..33),
                  "weather_code" => List.duplicate(0, length(times)),
                  "is_day" => List.duplicate(1, length(times))
                },
                "daily" => %{
                  "time" => dates,
                  "weather_code" => [0, 1, 2, 3],
                  "temperature_2m_max" => [24, 25, 26, 27],
                  "temperature_2m_min" => [12, 13, 14, 15]
                }
              }
            }
          }
        )

      {:ok, document} = Floki.parse_document(html)

      assert document |> Floki.find(".kw-w-forecast-col") |> length() == 4
      assert document |> Floki.find(".kw-w-forecast-day") |> length() == 4
      assert document |> Floki.find(".kw-w-forecast-hour") |> length() == 4
      assert document |> Floki.find(".kw-w-forecast-cell") |> length() == 16
      assert html =~ "30.05."
      assert html =~ "21:00"
    end

    test "shows today's rain chance as a headline stat when available" do
      html =
        render_component(&Weather.render/1,
          instance: %Instance{
            id: 125,
            config: %{
              "label" => "Berlin",
              "cached" => %{
                "current" => %{"temperature_2m" => 21.0, "weather_code" => 61, "is_day" => 1},
                "daily" => %{
                  "time" => ["2026-05-29"],
                  "temperature_2m_max" => [24],
                  "temperature_2m_min" => [12],
                  "precipitation_probability_max" => [70]
                }
              }
            }
          }
        )

      assert html =~ ~s(class="kw-w-stat kw-w-rain")
      assert html =~ "70%"
    end

    test "always renders the rain stat with a dash when probability is absent" do
      html =
        render_component(&Weather.render/1,
          instance: %Instance{
            id: 126,
            config: %{
              "label" => "Berlin",
              "cached" => %{
                "current" => %{"temperature_2m" => 21.0, "weather_code" => 0, "is_day" => 1},
                "daily" => %{
                  "time" => ["2026-05-29"],
                  "temperature_2m_max" => [24],
                  "temperature_2m_min" => [12]
                }
              }
            }
          }
        )

      # The row is always present (identical layout across sources); when the
      # source has no probability it shows the dash placeholder, never collapses.
      assert html =~ ~s(class="kw-w-stat kw-w-rain")
      assert html =~ "🌧 —"
    end
  end

  defp iso_local(dt) do
    "#{Date.to_iso8601(DateTime.to_date(dt))}T#{Time.to_iso8601(DateTime.to_time(dt)) |> String.slice(0, 5)}"
  end
end
