defmodule Kakemono.Widgets.Weather.Sources.MetNo do
  @moduledoc """
  MET Norway (yr.no) source. Free, no API key, but requires a non-generic
  `User-Agent` header (`config :kakemono, :met_no_user_agent`) or the API
  returns 403.

  Normalizes `locationforecast/2.0/compact` into the canonical Open-Meteo
  cache shape. Times are UTC and no sunrise/sunset is available, so
  `utc_offset_seconds` is omitted (the `WeatherSky` hook falls back to the
  host offset) and the sun-window chip stays hidden.
  """
  @behaviour Kakemono.Widgets.Weather.Source

  alias Kakemono.Widgets.Weather.Source

  @impl true
  def id, do: "met_no"

  @impl true
  def label, do: "MET Norway (yr.no)"

  @impl true
  def requires_key?, do: false

  @impl true
  def fetch(lat, lon, opts) do
    headers = [{"user-agent", user_agent()}]

    with {:ok, body} <- Source.fetch_json(url(lat, lon), [headers: headers], opts) do
      {:ok, normalize(body)}
    end
  end

  @doc "MET Norway compact forecast URL for a coordinate."
  def url(lat, lon) do
    "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=#{lat}&lon=#{lon}"
  end

  defp user_agent do
    Application.get_env(:kakemono, :met_no_user_agent, "Kakemono/1.0")
  end

  @doc "Normalize a MET Norway compact payload into the canonical cache shape."
  def normalize(body) do
    series = get_in(body, ["properties", "timeseries"]) || []
    first = List.first(series) || %{}
    details = get_in(first, ["data", "instant", "details"]) || %{}

    hourly_entries = Enum.take(series, 12)

    %{
      "current" => %{
        "time" => first["time"],
        "temperature_2m" => details["air_temperature"],
        "relative_humidity_2m" => details["relative_humidity"],
        "wind_speed_10m" => mps_to_kmh(details["wind_speed"]),
        "weather_code" => code(first),
        "is_day" => is_day_int(first)
      },
      "hourly" => %{
        "time" => Enum.map(hourly_entries, & &1["time"]),
        "temperature_2m" => Enum.map(hourly_entries, &temp/1),
        "weather_code" => Enum.map(hourly_entries, &code/1),
        "is_day" => Enum.map(hourly_entries, &is_day_int/1)
      },
      "daily" => daily(series)
    }
  end

  defp daily(series) do
    by_day = Enum.group_by(series, fn e -> date_of(e["time"]) end)
    dates = by_day |> Map.keys() |> Enum.reject(&is_nil/1) |> Enum.sort() |> Enum.take(6)

    %{
      "time" => dates,
      "temperature_2m_max" => Enum.map(dates, fn d -> day_temp(by_day[d], &Enum.max/1) end),
      "temperature_2m_min" => Enum.map(dates, fn d -> day_temp(by_day[d], &Enum.min/1) end),
      "weather_code" => Enum.map(dates, fn d -> midday_code(by_day[d]) end)
    }
  end

  defp day_temp(entries, agg) do
    case entries |> Enum.map(&temp/1) |> Enum.filter(&is_number/1) do
      [] -> nil
      temps -> agg.(temps)
    end
  end

  defp midday_code(entries) do
    entries
    |> Enum.min_by(fn e -> abs(hour_of(e["time"]) - 12) end, fn -> nil end)
    |> code()
  end

  defp temp(entry), do: get_in(entry, ["data", "instant", "details", "air_temperature"])

  defp symbol(entry) do
    get_in(entry, ["data", "next_1_hours", "summary", "symbol_code"]) ||
      get_in(entry, ["data", "next_6_hours", "summary", "symbol_code"])
  end

  defp code(nil), do: nil

  defp code(entry) do
    case symbol(entry) do
      nil -> nil
      sym -> sym |> condition() |> Source.wmo_for()
    end
  end

  defp condition(sym) do
    s = String.downcase(sym)

    cond do
      String.contains?(s, "thunder") -> :thunder
      String.contains?(s, "sleet") -> :sleet
      String.contains?(s, "snow") -> :snow
      String.contains?(s, "showers") -> :showers
      String.contains?(s, "rain") -> :rain
      String.contains?(s, "drizzle") -> :drizzle
      String.contains?(s, "fog") -> :fog
      String.contains?(s, "partlycloudy") -> :partly
      String.contains?(s, "fair") -> :partly
      String.contains?(s, "cloudy") -> :cloudy
      String.contains?(s, "clearsky") -> :clear
      true -> :clear
    end
  end

  defp is_day_int(entry) do
    case symbol(entry) do
      sym when is_binary(sym) -> if String.ends_with?(String.downcase(sym), "_night"), do: 0, else: 1
      _ -> 1
    end
  end

  defp mps_to_kmh(v) when is_number(v), do: Float.round(v * 3.6, 1)
  defp mps_to_kmh(_), do: nil

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
