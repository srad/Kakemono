defmodule Kakemono.Widgets.Weather.Source do
  @moduledoc """
  Behaviour + registry for selectable weather data sources.

  Every source normalizes its upstream response into the **canonical
  Open-Meteo cache shape** consumed by `Kakemono.Widgets.Weather.render/1`:

      %{
        "current" => %{"time", "temperature_2m", "weather_code", "is_day", ...},
        "hourly"  => %{"time" => [...], "temperature_2m" => [...],
                       "weather_code" => [...], "is_day" => [...]},
        "daily"   => %{"time" => [...], "weather_code" => [...],
                       "temperature_2m_max" => [...], "temperature_2m_min" => [...],
                       "sunrise" => [...], "sunset" => [...]},  # sun keys optional
        "utc_offset_seconds" => integer                          # optional
      }

  Non-Open-Meteo sources map their own condition tokens to a canonical
  condition atom and then to a **synthetic WMO code** via `wmo_for/1` (render
  only uses the code to pick a scene icon), and embed day/night into the
  `is_day` fields.
  """

  alias Kakemono.Widgets.Weather.Sources

  @callback id() :: String.t()
  @callback label() :: String.t()
  @callback requires_key?() :: boolean()
  @callback fetch(lat :: float, lon :: float, opts :: keyword) ::
              {:ok, map()} | {:error, term()}

  @sources [Sources.OpenMeteo, Sources.MetNo, Sources.BrightSky]

  @doc "All registered source modules."
  def sources, do: @sources

  @doc "Default source id used when a widget has no `source` configured."
  def default_id, do: Sources.OpenMeteo.id()

  @doc "`[{id, label}]` pairs for the editor `:select` field."
  def options, do: for(m <- @sources, do: {m.id(), m.label()})

  @doc "Look up a source module by id; nil if unknown."
  def fetch_by_id(id), do: Enum.find(@sources, fn m -> m.id() == id end)

  @doc "Source module for an id, falling back to the default source."
  def module(id), do: fetch_by_id(id) || Sources.OpenMeteo

  # ── Shared condition → synthetic WMO code table ─────────────────
  # Codes chosen so `Weather.weather_scene/2` resolves to the right icon.
  @wmo %{
    clear: 0,
    partly: 1,
    cloudy: 3,
    fog: 45,
    drizzle: 51,
    rain: 61,
    showers: 80,
    snow: 71,
    sleet: 71,
    thunder: 95
  }

  @doc "Synthetic WMO code for a canonical condition atom."
  def wmo_for(condition) when is_atom(condition), do: Map.get(@wmo, condition, 0)

  # ── Shared HTTP helper ──────────────────────────────────────────

  @doc """
  GET `url` expecting a JSON map body. `req_extra` is merged with the
  configured Req options (`opts[:req_options]` or `config :kakemono,
  :req_options`), so tests can stub via `Req.Test`.
  """
  def fetch_json(url, req_extra, opts) do
    base = Keyword.get(opts, :req_options) || Application.get_env(:kakemono, :req_options, [])

    case Req.get(url, Keyword.merge(req_extra, base)) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
