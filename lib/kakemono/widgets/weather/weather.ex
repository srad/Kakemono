defmodule Kakemono.Widgets.Weather do
  use Kakemono.Widget

  alias Kakemono.Widgets.{FetchWorker, Instance}
  alias Kakemono.Widgets.Weather.Source

  @impl true
  def type, do: "weather"

  @impl true
  def name, do: "Weather"

  @impl true
  def icon, do: "🌤"

  @impl true
  def draft_config, do: %{}

  @impl true
  def cache_fields, do: [{"cached", "object"}]

  @impl true
  def fields do
    [
      %{
        key: "label",
        label: "Location",
        type: :location_search,
        required: true,
        schema_optional: true,
        default: "Weather",
        placeholder: "Search a city…"
      },
      %{
        key: "latitude",
        type: :number,
        hidden: true,
        required: true,
        step: "any",
        min: -90,
        max: 90,
        default: 0.0
      },
      %{
        key: "longitude",
        type: :number,
        hidden: true,
        required: true,
        step: "any",
        min: -180,
        max: 180,
        default: 0.0
      },
      %{
        key: "timezone",
        type: :timezone_search,
        hidden: true,
        required: false,
        schema_optional: true,
        options: Kakemono.TimeZones.list()
      },
      %{
        key: "source",
        label: "Data source",
        type: :select,
        required: false,
        default: Source.default_id(),
        options: Source.options()
      },
      %{
        key: "api_key",
        label: "API key (optional)",
        type: :text,
        required: false,
        schema_optional: true,
        placeholder: "Only needed for key-based sources"
      },
      %{
        key: "forecast_layout",
        label: "Forecast layout",
        type: :select,
        required: false,
        default: "cards",
        options: [
          {"cards", "Day columns"},
          {"open", "Open (no panels)"},
          {"panel", "Single panel"}
        ]
      }
    ]
  end

  @impl true
  def prefetch(%Instance{id: id, config: cfg}) do
    if has_location?(cfg) and empty_cache?(cfg), do: enqueue_fetch(id)
    :ok
  end

  @impl true
  # Keep the existing cache across provider changes: every source normalizes to
  # the same canonical shape, so the last-known data keeps rendering until the
  # refetch (enqueued by on_config_change/2) replaces it — the widget never
  # blanks when the source/coordinates change.
  def merge_config(old, new), do: Map.merge(old, new)

  @impl true
  def on_config_change(%Instance{id: id, config: cfg}, old_config) do
    if has_location?(cfg) and provider_input_changed?(old_config, cfg), do: enqueue_fetch(id)
    :ok
  end

  @impl true
  def fetch(%Instance{config: cfg}) do
    source = Source.module(cfg["source"])

    with {:ok, body} <- source.fetch(cfg["latitude"], cfg["longitude"], api_key: cfg["api_key"]) do
      {:ok, %{"cached" => body}}
    end
  end

  defp has_location?(cfg) do
    lat = cfg["latitude"]
    lon = cfg["longitude"]
    is_number(lat) and is_number(lon) and not (lat == 0.0 and lon == 0.0)
  end

  defp empty_cache?(cfg) do
    cached = cfg["cached"]
    is_nil(cached) or cached == %{}
  end

  # True when the fields that determine the upstream response (source, key, or
  # coordinates) differ between two configs. Drives cache invalidation + refetch.
  defp provider_input_changed?(old, new) do
    norm(old["source"]) != norm(new["source"]) or
      norm(old["api_key"]) != norm(new["api_key"]) or
      old["latitude"] != new["latitude"] or
      old["longitude"] != new["longitude"]
  end

  defp norm(nil), do: nil
  defp norm(""), do: nil
  defp norm(v), do: v

  defp enqueue_fetch(id) do
    %{instance_id: id} |> FetchWorker.new() |> Oban.insert!()
  end

  @impl true
  def render(assigns) do
    cfg = assigns.instance.config
    cached = cfg["cached"] || %{}
    current = cached["current"] || %{}
    preview_cond = preview_cond(cfg["__preview_cond"])
    preview_tod = preview_tod(cfg["__preview_tod"])

    is_day? = if preview_tod, do: preview_is_day?(preview_tod), else: compute_is_day(cached)
    code = preview_code(preview_cond) || current["weather_code"]
    cond = preview_cond || weather_cond(code)
    today = (cached["daily"] || %{}) |> daily_today()

    assigns =
      Map.merge(assigns, %{
        cond: Atom.to_string(cond),
        is_day: if(is_day?, do: "1", else: "0"),
        tod: preview_tod || if(is_day?, do: "day", else: "night"),
        preview_tod: preview_tod,
        weather_id: "weather-" <> Integer.to_string(assigns.instance.id),
        latitude: cfg["latitude"],
        longitude: cfg["longitude"],
        timezone: cfg["timezone"],
        utc_offset: utc_offset_for(cfg, cached),
        label: cfg["label"] || "Weather",
        temp: format_temperature(current["temperature_2m"]),
        feels_like: format_temperature(current["apparent_temperature"]),
        humidity: current["relative_humidity_2m"],
        wind: format_wind(current["wind_speed_10m"]),
        condition: weather_condition(code),
        hi: format_temperature(today["max"]),
        lo: format_temperature(today["min"]),
        rain: format_percent(today["precip"]),
        sun_window: format_sun_window(today["sunrise"], today["sunset"]),
        today_date: format_today(today["date"]),
        hourly: next_hours(cached, 12),
        daily: next_days(cached, 3),
        forecast_grid: forecast_grid(cached, 4, [3, 6, 9, 12, 15, 18, 21, 0]),
        forecast_layout: cfg["forecast_layout"] || "cards"
      })

    ~H"""
    <div
      id={@weather_id}
      phx-hook="WeatherSky"
      class="kakemono-widget kakemono-widget-weather"
      data-cond={@cond}
      data-is-day={@is_day}
      data-tod={@tod}
      data-latitude={@latitude}
      data-longitude={@longitude}
      data-timezone={@timezone}
      data-utc-offset={@utc_offset}
      data-preview-tod={@preview_tod}
    >
      <div class="kw-w-sky" aria-hidden="true">
        <div class="kw-w-stars"></div>
        <div class="kw-w-horizon"></div>
        <div class="kw-w-sun-body"></div>
        <div class="kw-w-moon-body"></div>
        <div class="kw-w-cloudfield">
          <div class="kw-w-cloudband kw-w-cloudband--far"></div>
          <div class="kw-w-cloudband kw-w-cloudband--near"></div>
        </div>
        <div class="kw-w-atmosphere"></div>
      </div>
      <div class={
        if @forecast_grid != nil, do: "kw-w-content kw-w-content-table", else: "kw-w-content"
      }>
        <div class="kw-w-header">
          <span class="kw-w-loc">{@label}</span>
          <span :if={@today_date != ""} class="kw-w-sep">·</span>
          <span class="kw-w-day">{@today_date}</span>
        </div>

        <div class="kw-w-hero">
          <div class="kw-w-hero-icon">
            <.weather_icon scene={@cond} />
          </div>
          <div class="kw-w-hero-text">
            <div class="kw-w-temp">{@temp}</div>
            <div class="kw-w-cond">{@condition}</div>
            <div :if={@feels_like != "—°"} class="kw-w-feels">Feels like {@feels_like}</div>
          </div>
          <div class="kw-w-stats">
            <div :if={@hi != "—°"} class="kw-w-stat kw-w-hi">
              <span class="kw-w-stat-icon" aria-hidden="true">↑</span>
              <span class="kw-w-stat-label">High</span>
              <span class="kw-w-stat-val">{@hi}</span>
            </div>
            <div :if={@lo != "—°"} class="kw-w-stat kw-w-lo">
              <span class="kw-w-stat-icon" aria-hidden="true">↓</span>
              <span class="kw-w-stat-label">Low</span>
              <span class="kw-w-stat-val">{@lo}</span>
            </div>
            <div :if={@rain != nil} class="kw-w-stat kw-w-rain">
              <span class="kw-w-stat-icon" aria-hidden="true">🌧</span>
              <span class="kw-w-stat-label">Rain</span>
              <span class="kw-w-stat-val">{@rain}</span>
            </div>
            <div :if={is_number(@humidity)} class="kw-w-stat kw-w-humidity">
              <span class="kw-w-stat-icon" aria-hidden="true">🌫</span>
              <span class="kw-w-stat-label">Humidity</span>
              <span class="kw-w-stat-val">{round(@humidity)}%</span>
            </div>
            <div :if={@wind != nil} class="kw-w-stat kw-w-wind">
              <span class="kw-w-stat-icon" aria-hidden="true">🌬</span>
              <span class="kw-w-stat-label">Wind</span>
              <span class="kw-w-stat-val">{@wind}</span>
            </div>
            <div :if={@sun_window != nil} class="kw-w-stat kw-w-sun">
              <span class="kw-w-stat-icon" aria-hidden="true">🌅</span>
              <span class="kw-w-stat-label">Sun</span>
              <span class="kw-w-stat-val">{@sun_window}</span>
            </div>
          </div>
        </div>

        <div
          :if={@forecast_grid != nil}
          class="kw-w-forecast-table"
          data-layout={@forecast_layout}
          role="table"
          aria-label="Weather forecast by day and hour"
        >
          <div class="kw-w-forecast-rail" role="rowgroup">
            <div class="kw-w-forecast-corner"></div>
            <div
              :for={hour <- @forecast_grid.hours}
              class="kw-w-forecast-hour"
              role="rowheader"
              data-tier={hour.tier}
            >
              {hour.label}
            </div>
          </div>

          <div :for={col <- @forecast_grid.columns} class="kw-w-forecast-col" role="column">
            <div class="kw-w-forecast-day" role="columnheader">
              <span class="kw-w-forecast-weekday">{col.weekday}</span>
              <span class="kw-w-forecast-date">{col.date}</span>
            </div>
            <div
              :for={cell <- col.cells}
              class={["kw-w-forecast-cell", cell.temp == nil && "kw-w-forecast-cell-empty"]}
              data-scene={cell.scene}
              data-tier={cell.tier}
              role="cell"
            >
              <div :if={cell.temp != nil} class="kw-w-forecast-cell-main">
                <span class="kw-w-forecast-icon"><.weather_icon scene={cell.scene} small /></span>
                <span class="kw-w-forecast-temp">{cell.temp}</span>
              </div>
              <span :if={cell.temp == nil} class="kw-w-forecast-dash">–</span>
            </div>
          </div>
        </div>

        <div :if={@forecast_grid == nil and @hourly != []} class="kw-w-hourly">
          <div :for={h <- @hourly} class="kw-w-hourly-cell">
            <div class="kw-w-hourly-time">{h.label}</div>
            <div class="kw-w-hourly-icon"><.weather_icon scene={h.scene} small /></div>
            <div class="kw-w-hourly-temp">{h.temp}</div>
          </div>
        </div>

        <div :if={@forecast_grid == nil and @daily != []} class="kw-w-daily">
          <div :for={d <- @daily} class="kw-w-daily-row">
            <div class="kw-w-daily-day">{d.label}</div>
            <div class="kw-w-daily-icon"><.weather_icon scene={d.scene} small /></div>
            <div class="kw-w-daily-lo">{d.lo}</div>
            <div class="kw-w-daily-bar">
              <span
                class="kw-w-daily-bar-fill"
                style={daily_bar_style(d, @daily)}
              >
              </span>
            </div>
            <div class="kw-w-daily-hi">{d.hi}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Icon component ──────────────────────────────────────────────

  attr :scene, :string, required: true
  attr :small, :boolean, default: false

  # Icon paths adapted from Lucide (https://lucide.dev), ISC License.
  # 24x24 viewBox, stroke-based — fill/stroke styled via .kw-w-icon CSS rule.
  defp weather_icon(assigns) do
    ~H"""
    <svg
      class={["kw-w-icon", @small && "kw-w-icon-sm"]}
      data-scene={@scene}
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <%= case @scene do %>
        <% "clear" -> %>
          <g class="kw-w-sun">
            <circle class="kw-w-sun-core" cx="12" cy="12" r="4" fill="currentColor" />
            <g class="kw-w-sun-rays">
              <path d="M12 2v2" />
              <path d="M12 20v2" />
              <path d="m4.93 4.93 1.41 1.41" />
              <path d="m17.66 17.66 1.41 1.41" />
              <path d="M2 12h2" />
              <path d="M20 12h2" />
              <path d="m6.34 17.66-1.41 1.41" />
              <path d="m19.07 4.93-1.41 1.41" />
            </g>
          </g>
          <path
            class="kw-w-moon"
            d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"
            fill="currentColor"
            fill-opacity="0.85"
          />
        <% "clear_day" -> %>
          <circle class="kw-w-sun-core" cx="12" cy="12" r="4" fill="currentColor" />
          <g class="kw-w-sun-rays">
            <path d="M12 2v2" />
            <path d="M12 20v2" />
            <path d="m4.93 4.93 1.41 1.41" />
            <path d="m17.66 17.66 1.41 1.41" />
            <path d="M2 12h2" />
            <path d="M20 12h2" />
            <path d="m6.34 17.66-1.41 1.41" />
            <path d="m19.07 4.93-1.41 1.41" />
          </g>
        <% "clear_night" -> %>
          <path
            class="kw-w-moon"
            d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"
            fill="currentColor"
            fill-opacity="0.85"
          />
        <% "partly" -> %>
          <g class="kw-w-sun">
            <path d="M12 2v2" />
            <path d="m4.93 4.93 1.41 1.41" />
            <path d="M20 12h2" />
            <path d="m19.07 4.93-1.41 1.41" />
            <path d="M15.947 12.65a4 4 0 0 0-5.925-4.128" />
          </g>
          <path class="kw-w-cloud" d="M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6Z" />
        <% "cloudy" -> %>
          <path class="kw-w-cloud" d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
        <% "fog" -> %>
          <path class="kw-w-cloud" d="M16 17H7a5 5 0 1 1 4.9-6H17a3 3 0 0 1 0 6h-1" />
          <g class="kw-w-fog-lines">
            <path d="M16 21H7" />
            <path d="M19 21h-3" />
            <path d="M11 13H3" />
          </g>
        <% "drizzle" -> %>
          <path class="kw-w-cloud" d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
          <g class="kw-w-rain">
            <path d="M8 19v1" />
            <path d="M8 14v1" />
            <path d="M16 19v1" />
            <path d="M16 14v1" />
            <path d="M12 21v1" />
            <path d="M12 16v1" />
          </g>
        <% s when s in ["rain", "showers"] -> %>
          <path class="kw-w-cloud" d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
          <g class="kw-w-rain">
            <path d="M16 14v6" />
            <path d="M8 14v6" />
            <path d="M12 16v6" />
          </g>
        <% "snow" -> %>
          <path class="kw-w-cloud" d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
          <g class="kw-w-snow">
            <path d="M8 15h.01" />
            <path d="M8 19h.01" />
            <path d="M12 17h.01" />
            <path d="M12 21h.01" />
            <path d="M16 15h.01" />
            <path d="M16 19h.01" />
          </g>
        <% "thunder" -> %>
          <path class="kw-w-cloud" d="M6 16.326A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 .5 8.973" />
          <path class="kw-w-bolt" d="m13 12-3 5h4l-3 5" />
        <% _ -> %>
          <circle cx="12" cy="12" r="4" fill="currentColor" />
      <% end %>
    </svg>
    """
  end

  # ── Day/night logic (uses location-local sunrise/sunset) ────────

  @doc false
  def compute_is_day(cached) do
    offset = cached["utc_offset_seconds"] || 0

    sunrise =
      parse_local(get_in(cached, ["daily", "sunrise"]) |> List.wrap() |> List.first(), offset)

    sunset =
      parse_local(get_in(cached, ["daily", "sunset"]) |> List.wrap() |> List.first(), offset)

    now_local = DateTime.utc_now() |> DateTime.add(offset, :second)

    is_day_for(now_local, sunrise, sunset, fallback_is_day(cached))
  end

  @doc """
  Pure version of the day/night decision, exposed for unit tests.
  Returns true if `now` is between sunrise (inclusive) and sunset (exclusive).
  Falls back to `fallback` if either bound is nil.
  """
  def is_day_for(%DateTime{} = now, %DateTime{} = sunrise, %DateTime{} = sunset, _fallback) do
    DateTime.compare(now, sunrise) != :lt and DateTime.compare(now, sunset) == :lt
  end

  def is_day_for(_, _, _, fallback), do: fallback

  defp fallback_is_day(cached) do
    case get_in(cached, ["current", "is_day"]) do
      0 -> false
      _ -> true
    end
  end

  defp utc_offset_for(cfg, cached) do
    case cfg["source"] do
      nil -> Map.get(cached, "utc_offset_seconds")
      "" -> Map.get(cached, "utc_offset_seconds")
      "open_meteo" -> Map.get(cached, "utc_offset_seconds")
      _ -> nil
    end
  end

  defp parse_local(nil, _offset), do: nil

  defp parse_local(
         <<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2), "T",
           hh::binary-size(2), ":", mm::binary-size(2), _rest::binary>>,
         offset
       ) do
    with {yi, ""} <- Integer.parse(y),
         {mi, ""} <- Integer.parse(m),
         {di, ""} <- Integer.parse(d),
         {hhi, ""} <- Integer.parse(hh),
         {mmi, ""} <- Integer.parse(mm),
         {:ok, naive} <- NaiveDateTime.new(yi, mi, di, hhi, mmi, 0),
         # The Open-Meteo string is local wall-clock time. Convert to UTC then
         # back to a DateTime shifted by the same offset so all timestamps
         # compared share the same offset basis.
         {:ok, utc} <- DateTime.from_naive(naive, "Etc/UTC") do
      DateTime.add(utc, -offset, :second) |> DateTime.add(offset, :second)
    else
      _ -> nil
    end
  end

  defp parse_local(_, _), do: nil

  # ── Scene mapping ───────────────────────────────────────────────

  # Day/night-neutral condition for the hero. Day vs night is decided live by
  # the WeatherSky hook via data-tod, so the hero icon (combined sun+moon for
  # :clear) and gradient stay in sync with the location's current local time
  # regardless of when the cache was fetched.
  defp weather_cond(code) do
    cond do
      not is_integer(code) -> :clear
      code == 0 -> :clear
      code in 1..2 -> :partly
      code == 3 -> :cloudy
      code in 45..48 -> :fog
      code in 51..57 -> :drizzle
      code in 61..67 -> :rain
      code in 71..77 -> :snow
      code in 80..82 -> :showers
      code in 85..86 -> :snow
      code in 95..99 -> :thunder
      true -> :clear
    end
  end

  defp weather_scene(code, is_day?) do
    cond do
      not is_integer(code) -> if is_day?, do: :clear_day, else: :clear_night
      code == 0 and is_day? -> :clear_day
      code == 0 -> :clear_night
      code in 1..2 -> :partly
      code == 3 -> :cloudy
      code in 45..48 -> :fog
      code in 51..57 -> :drizzle
      code in 61..67 -> :rain
      code in 71..77 -> :snow
      code in 80..82 -> :showers
      code in 85..86 -> :snow
      code in 95..99 -> :thunder
      true -> if is_day?, do: :clear_day, else: :clear_night
    end
  end

  defp weather_condition(code) when is_integer(code) do
    cond do
      code == 0 -> "Clear"
      code in 1..2 -> "Mostly clear"
      code == 3 -> "Overcast"
      code in 45..48 -> "Fog"
      code in 51..57 -> "Drizzle"
      code in 61..67 -> "Rain"
      code in 71..77 -> "Snow"
      code in 80..82 -> "Showers"
      code in 85..86 -> "Snow showers"
      code in 95..99 -> "Thunderstorm"
      true -> "—"
    end
  end

  defp weather_condition(_), do: "—"

  defp preview_cond("clear"), do: :clear
  defp preview_cond("partly"), do: :partly
  defp preview_cond("cloudy"), do: :cloudy
  defp preview_cond("fog"), do: :fog
  defp preview_cond("drizzle"), do: :drizzle
  defp preview_cond("rain"), do: :rain
  defp preview_cond("showers"), do: :showers
  defp preview_cond("snow"), do: :snow
  defp preview_cond("thunder"), do: :thunder
  defp preview_cond(_), do: nil

  defp preview_tod(value) when value in ~w(day dawn dusk night), do: value
  defp preview_tod(_), do: nil

  defp preview_is_day?("night"), do: false
  defp preview_is_day?(_), do: true

  defp preview_code(:clear), do: 0
  defp preview_code(:partly), do: 1
  defp preview_code(:cloudy), do: 3
  defp preview_code(:fog), do: 45
  defp preview_code(:drizzle), do: 51
  defp preview_code(:rain), do: 61
  defp preview_code(:showers), do: 80
  defp preview_code(:snow), do: 71
  defp preview_code(:thunder), do: 95
  defp preview_code(_), do: nil

  defp daily_today(%{"time" => [date | _]} = daily) do
    %{
      "date" => date,
      "max" => List.first(daily["temperature_2m_max"] || []),
      "min" => List.first(daily["temperature_2m_min"] || []),
      "precip" => List.first(daily["precipitation_probability_max"] || []),
      "sunrise" => List.first(daily["sunrise"] || []),
      "sunset" => List.first(daily["sunset"] || [])
    }
  end

  defp daily_today(_), do: %{}

  @doc false
  def next_hours(%{"hourly" => %{"time" => times} = h, "current" => %{"time" => now}}, take)
      when is_list(times) do
    start_index =
      Enum.find_index(times, fn t -> t >= now end) || 0

    times = Enum.slice(times, start_index, take)
    temps = Enum.slice(h["temperature_2m"] || [], start_index, take)
    codes = Enum.slice(h["weather_code"] || [], start_index, take)
    days = Enum.slice(h["is_day"] || [], start_index, take)

    Enum.zip([times, temps, codes, days])
    |> Enum.map(fn {t, temp, code, isd} ->
      %{
        label: format_hour_label(t),
        temp: format_temperature(temp),
        scene: weather_scene(code, isd == 1) |> Atom.to_string()
      }
    end)
  end

  def next_hours(_, _), do: []

  @doc false
  def next_days(%{"daily" => %{"time" => times} = d}, take) when is_list(times) do
    start_index = 1

    times = Enum.slice(times, start_index, take)
    codes = Enum.slice(d["weather_code"] || [], start_index, take)
    hi = Enum.slice(d["temperature_2m_max"] || [], start_index, take)
    lo = Enum.slice(d["temperature_2m_min"] || [], start_index, take)

    Enum.zip([times, codes, hi, lo])
    |> Enum.map(fn {t, code, h, l} ->
      %{
        label: format_weekday(t),
        scene: weather_scene(code, true) |> Atom.to_string(),
        hi: format_temperature(h),
        lo: format_temperature(l),
        hi_n: if(is_number(h), do: h, else: nil),
        lo_n: if(is_number(l), do: l, else: nil)
      }
    end)
  end

  def next_days(_, _), do: []

  @forecast_hour_tiers %{
    6 => 1, 12 => 1, 18 => 1,
    15 => 2, 21 => 2,
    0 => 3,
    3 => 4, 9 => 4
  }

  defp forecast_grid(%{"hourly" => %{"time" => times} = hourly} = cached, day_count, hours)
       when is_list(times) do
    points = hourly_points(hourly, hours)
    dates = forecast_dates(cached, times, day_count)

    cond do
      dates == [] -> nil
      map_size(points) == 0 -> nil
      true -> build_forecast_grid(dates, hours, points)
    end
  end

  defp forecast_grid(_, _, _), do: nil

  defp hourly_points(hourly, hours) do
    times = hourly["time"] || []
    temps = hourly["temperature_2m"] || []
    codes = hourly["weather_code"] || []
    days = hourly["is_day"] || List.duplicate(1, length(times))
    hour_set = MapSet.new(hours)

    Enum.zip([times, temps, codes, days])
    |> Enum.reduce(%{}, fn {time, temp, code, is_day}, acc ->
      case date_hour(time) do
        {date, hour} ->
          if MapSet.member?(hour_set, hour) do
            Map.put(acc, {date, hour}, %{
              temp: format_temperature(temp),
              scene: weather_scene(code, is_day == 1) |> Atom.to_string()
            })
          else
            acc
          end

        nil ->
          acc
      end
    end)
  end

  defp forecast_dates(cached, hourly_times, count) do
    dates =
      case get_in(cached, ["daily", "time"]) do
        daily_dates when is_list(daily_dates) and daily_dates != [] ->
          daily_dates

        _ ->
          hourly_times
          |> Enum.map(&date_part/1)
          |> Enum.reject(&is_nil/1)
      end

    dates
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.take(count)
  end

  defp build_forecast_grid(dates, hours, points) do
    %{
      hours:
        Enum.map(hours, fn hour ->
          %{label: format_hour_slot(hour), tier: Map.get(@forecast_hour_tiers, hour, 4)}
        end),
      columns:
        Enum.map(dates, fn date ->
          %{
            weekday: format_weekday(date),
            date: format_forecast_date(date),
            cells:
              Enum.map(hours, fn hour ->
                Map.get(points, {date, hour}, empty_forecast_cell())
                |> Map.put(:tier, Map.get(@forecast_hour_tiers, hour, 4))
              end)
          }
        end)
    }
  end

  defp empty_forecast_cell, do: %{temp: nil, scene: nil}

  defp date_hour(<<date::binary-size(10), "T", hh::binary-size(2), ":", _::binary>>) do
    with {hour, ""} <- Integer.parse(hh) do
      {date, hour}
    else
      _ -> nil
    end
  end

  defp date_hour(_), do: nil

  defp date_part(<<date::binary-size(10), "T", _::binary>>), do: date
  defp date_part(_), do: nil

  # Compute the range-bar fill position for one daily row, scaled across
  # the whole displayed week's min/max range.
  defp daily_bar_style(day, all_days) do
    {global_lo, global_hi} = global_range(all_days)
    span = global_hi - global_lo

    cond do
      span <= 0 ->
        "left: 0%; right: 0%;"

      is_nil(day.hi_n) or is_nil(day.lo_n) ->
        "left: 0%; right: 0%;"

      true ->
        left = (day.lo_n - global_lo) / span * 100
        right = (global_hi - day.hi_n) / span * 100
        "left: #{Float.round(left, 1)}%; right: #{Float.round(right, 1)}%;"
    end
  end

  defp global_range(days) do
    nums = Enum.flat_map(days, fn d -> Enum.filter([d.lo_n, d.hi_n], &is_number/1) end)

    case nums do
      [] -> {0.0, 1.0}
      _ -> {Enum.min(nums) * 1.0, Enum.max(nums) * 1.0}
    end
  end

  # ── Formatters ──────────────────────────────────────────────────

  defp format_temperature(t) when is_number(t), do: "#{round(t)}°"
  defp format_temperature(_), do: "—°"

  defp format_wind(nil), do: nil
  defp format_wind(v) when is_number(v), do: "#{round(v)} km/h"
  defp format_wind(_), do: nil

  defp format_percent(v) when is_number(v), do: "#{round(v)}%"
  defp format_percent(_), do: nil

  defp format_hour_label(
         <<_y::binary-size(4), "-", _m::binary-size(2), "-", _d::binary-size(2), "T",
           hh::binary-size(2), ":", _mm::binary-size(2), _rest::binary>>
       ) do
    "#{hh}:00"
  end

  defp format_hour_label(_), do: ""

  defp format_hour_slot(hour) when is_integer(hour) do
    "#{String.pad_leading(Integer.to_string(hour), 2, "0")}:00"
  end

  defp format_hour_slot(_), do: ""

  defp format_clock(
         <<_::binary-size(11), hh::binary-size(2), ":", mm::binary-size(2), _::binary>>
       ) do
    "#{hh}:#{mm}"
  end

  defp format_clock(_), do: nil

  defp format_sun_window(sunrise, sunset) do
    case {format_clock(sunrise), format_clock(sunset)} do
      {sr, ss} when is_binary(sr) and is_binary(ss) -> "#{sr} · #{ss}"
      _ -> nil
    end
  end

  @weekdays {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

  defp format_weekday(<<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2)>>) do
    with {yi, ""} <- Integer.parse(y),
         {mi, ""} <- Integer.parse(m),
         {di, ""} <- Integer.parse(d),
         {:ok, date} <- Date.new(yi, mi, di) do
      elem(@weekdays, Date.day_of_week(date) - 1)
    else
      _ -> ""
    end
  end

  defp format_weekday(_), do: ""

  defp format_forecast_date(
         <<_y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2)>>
       ) do
    "#{d}.#{m}."
  end

  defp format_forecast_date(_), do: ""

  @months {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

  defp format_today(<<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2)>>) do
    with {yi, ""} <- Integer.parse(y),
         {mi, ""} <- Integer.parse(m),
         {di, ""} <- Integer.parse(d),
         {:ok, date} <- Date.new(yi, mi, di) do
      "#{elem(@weekdays, Date.day_of_week(date) - 1)}, #{elem(@months, mi - 1)} #{di}"
    else
      _ -> ""
    end
  end

  defp format_today(_), do: ""
end
