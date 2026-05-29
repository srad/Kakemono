defmodule Kakemono.Widgets.Weather.Sources.BrightSky do
  @moduledoc """
  Bright Sky (brightsky.dev) source — free, no API key, official Deutscher
  Wetterdienst data with strong German coverage.

  Combines `/current_weather` (current conditions) and `/weather` (a ~6-day
  hourly range) into the canonical Open-Meteo cache shape. Day/night comes
  from the icon suffix (`-day`/`-night`) with an hour-of-day fallback;
  `utc_offset_seconds` is parsed from the returned timestamps.
  """
  @behaviour Kakemono.Widgets.Weather.Source

  alias Kakemono.Widgets.Weather.Source

  @impl true
  def id, do: "bright_sky"

  @impl true
  def label, do: "Bright Sky (DWD)"

  @impl true
  def requires_key?, do: false

  @impl true
  def fetch(lat, lon, opts) do
    with {:ok, current} <- Source.fetch_json(current_url(lat, lon), [], opts),
         {:ok, range} <- Source.fetch_json(range_url(lat, lon), [], opts) do
      {:ok, normalize(current, range)}
    end
  end

  @doc "Bright Sky current-weather URL for a coordinate."
  def current_url(lat, lon) do
    "https://api.brightsky.dev/current_weather?lat=#{lat}&lon=#{lon}"
  end

  @doc "Bright Sky hourly-range URL (~6 days from today) for a coordinate."
  def range_url(lat, lon, today \\ Date.utc_today()) do
    last = Date.add(today, 6)
    "https://api.brightsky.dev/weather?lat=#{lat}&lon=#{lon}&date=#{today}&last_date=#{last}"
  end

  @doc "Normalize Bright Sky current + range payloads into the canonical cache shape."
  def normalize(current, range) do
    w = current["weather"] || %{}
    records = range["weather"] || []

    result = %{
      "current" => %{
        "time" => w["timestamp"],
        "temperature_2m" => w["temperature"],
        "relative_humidity_2m" => w["relative_humidity"],
        "wind_speed_10m" => w["wind_speed"],
        "weather_code" => icon_code(w["icon"]),
        "is_day" => is_day_int(w["icon"], w["timestamp"])
      },
      "hourly" => %{
        "time" => Enum.map(records, & &1["timestamp"]),
        "temperature_2m" => Enum.map(records, & &1["temperature"]),
        "weather_code" => Enum.map(records, &icon_code(&1["icon"])),
        "is_day" => Enum.map(records, &is_day_int(&1["icon"], &1["timestamp"]))
      },
      "daily" => daily(records)
    }

    case parse_offset(w["timestamp"]) do
      nil -> result
      offset -> Map.put(result, "utc_offset_seconds", offset)
    end
  end

  defp daily(records) do
    by_day = Enum.group_by(records, fn r -> date_of(r["timestamp"]) end)
    dates = by_day |> Map.keys() |> Enum.reject(&is_nil/1) |> Enum.sort() |> Enum.take(6)

    %{
      "time" => dates,
      "temperature_2m_max" => Enum.map(dates, fn d -> day_temp(by_day[d], &Enum.max/1) end),
      "temperature_2m_min" => Enum.map(dates, fn d -> day_temp(by_day[d], &Enum.min/1) end),
      "precipitation_probability_max" => Enum.map(dates, fn d -> day_precip_prob(by_day[d]) end),
      "weather_code" => Enum.map(dates, fn d -> midday_code(by_day[d]) end)
    }
  end

  defp day_temp(records, agg) do
    case records |> Enum.map(& &1["temperature"]) |> Enum.filter(&is_number/1) do
      [] -> nil
      temps -> agg.(temps)
    end
  end

  defp day_precip_prob(records) do
    case records |> Enum.map(& &1["precipitation_probability"]) |> Enum.filter(&is_number/1) do
      [] -> nil
      probs -> Enum.max(probs)
    end
  end

  defp midday_code(records) do
    record = Enum.min_by(records, fn r -> abs(hour_of(r["timestamp"]) - 12) end, fn -> nil end)
    icon_code(record && record["icon"])
  end

  defp icon_code(icon) when is_binary(icon), do: icon |> condition() |> Source.wmo_for()
  defp icon_code(_), do: nil

  defp condition(icon) do
    cond do
      String.contains?(icon, "thunder") -> :thunder
      String.contains?(icon, "sleet") -> :sleet
      String.contains?(icon, "snow") -> :snow
      String.contains?(icon, "hail") -> :showers
      String.contains?(icon, "rain") -> :rain
      String.contains?(icon, "partly-cloudy") -> :partly
      String.contains?(icon, "cloudy") -> :cloudy
      String.contains?(icon, "fog") -> :fog
      String.contains?(icon, "wind") -> :cloudy
      String.contains?(icon, "clear") -> :clear
      true -> :clear
    end
  end

  defp is_day_int(icon, timestamp) do
    cond do
      is_binary(icon) and String.ends_with?(icon, "-night") -> 0
      is_binary(icon) and String.ends_with?(icon, "-day") -> 1
      true -> if day_hour?(timestamp), do: 1, else: 0
    end
  end

  defp day_hour?(timestamp) do
    h = hour_of(timestamp)
    h >= 6 and h < 20
  end

  # "2026-05-28T12:00:00+02:00" -> 7200, "...Z" -> 0
  defp parse_offset(ts) when is_binary(ts) do
    cond do
      String.ends_with?(ts, "Z") ->
        0

      m = Regex.run(~r/([+-])(\d{2}):(\d{2})$/, ts) ->
        [_, sign, hh, mm] = m
        secs = String.to_integer(hh) * 3600 + String.to_integer(mm) * 60
        if sign == "-", do: -secs, else: secs

      true ->
        nil
    end
  end

  defp parse_offset(_), do: nil

  defp date_of(<<d::binary-size(10), _::binary>>), do: d
  defp date_of(_), do: nil

  defp hour_of(<<_::binary-size(11), hh::binary-size(2), _::binary>>) do
    case Integer.parse(hh) do
      {h, _} -> h
      _ -> 0
    end
  end

  defp hour_of(_), do: 0
end
