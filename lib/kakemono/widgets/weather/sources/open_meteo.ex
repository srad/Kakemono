defmodule Kakemono.Widgets.Weather.Sources.OpenMeteo do
  @moduledoc """
  Open-Meteo source — the original default. Its response is already the
  canonical shape, so `fetch/3` is a passthrough (no normalization).
  """
  @behaviour Kakemono.Widgets.Weather.Source

  alias Kakemono.Widgets.Weather.Source

  @impl true
  def id, do: "open_meteo"

  @impl true
  def label, do: "Open-Meteo"

  @impl true
  def requires_key?, do: false

  @impl true
  def fetch(lat, lon, opts), do: Source.fetch_json(url(lat, lon), [], opts)

  @doc "Open-Meteo forecast URL for a coordinate."
  def url(lat, lon) do
    "https://api.open-meteo.com/v1/forecast" <>
      "?latitude=#{lat}&longitude=#{lon}" <>
      "&current=temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m,is_day" <>
      "&hourly=temperature_2m,weather_code,is_day" <>
      "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset" <>
      "&forecast_days=7&timezone=auto"
  end
end
