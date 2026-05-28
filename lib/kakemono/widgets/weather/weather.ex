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
      }
    ]
  end

  @impl true
  def prefetch(%Instance{id: id, config: cfg}) do
    if has_location?(cfg) and empty_cache?(cfg), do: enqueue_fetch(id)
    :ok
  end

  @impl true
  def merge_config(old, new) do
    merged = Map.merge(old, new)
    if provider_input_changed?(old, merged), do: Map.delete(merged, "cached"), else: merged
  end

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

    is_day? = compute_is_day(cached)
    code = current["weather_code"]
    scene = weather_scene(code, is_day?)
    today = (cached["daily"] || %{}) |> daily_today()

    assigns =
      Map.merge(assigns, %{
        scene: Atom.to_string(scene),
        is_day: if(is_day?, do: "1", else: "0"),
        tod: if(is_day?, do: "day", else: "night"),
        weather_id: "weather-" <> Integer.to_string(assigns.instance.id),
        latitude: cfg["latitude"],
        longitude: cfg["longitude"],
        utc_offset: cached["utc_offset_seconds"] || 0,
        label: cfg["label"] || "Weather",
        temp: format_temperature(current["temperature_2m"]),
        feels_like: format_temperature(current["apparent_temperature"]),
        humidity: current["relative_humidity_2m"],
        wind: format_wind(current["wind_speed_10m"]),
        condition: weather_condition(code),
        hi: format_temperature(today["max"]),
        lo: format_temperature(today["min"]),
        sun_window: format_sun_window(today["sunrise"], today["sunset"]),
        today_date: format_today(today["date"]),
        hourly: next_hours(cached, 12),
        daily: next_days(cached, 5)
      })

    ~H"""
    <div
      id={@weather_id}
      phx-hook="WeatherSky"
      class="kakemono-widget kakemono-widget-weather"
      data-cond={@scene}
      data-is-day={@is_day}
      data-tod={@tod}
      data-latitude={@latitude}
      data-longitude={@longitude}
      data-utc-offset={@utc_offset}
    >
      <div class="kw-w-content">
        <div class="kw-w-header">
          <span class="kw-w-loc">{@label}</span>
          <span :if={@today_date != ""} class="kw-w-sep">·</span>
          <span class="kw-w-day">{@today_date}</span>
        </div>

        <div class="kw-w-hero">
          <div class="kw-w-hero-icon">
            <.weather_icon scene={@scene} />
          </div>
          <div class="kw-w-hero-text">
            <div class="kw-w-temp">{@temp}</div>
            <div class="kw-w-cond">{@condition}</div>
            <div class="kw-w-hilo">
              <span class="kw-w-hi">↑ {@hi}</span>
              <span class="kw-w-lo">↓ {@lo}</span>
            </div>
            <div :if={@feels_like != "—°"} class="kw-w-feels">Feels like {@feels_like}</div>
          </div>
        </div>

        <div class="kw-w-chips">
          <span :if={is_number(@humidity)} class="kw-w-chip">
            <span class="kw-w-chip-icon" aria-hidden="true">💧</span>{round(@humidity)}%
          </span>
          <span :if={@wind != nil} class="kw-w-chip">
            <span class="kw-w-chip-icon" aria-hidden="true">🌬</span>{@wind}
          </span>
          <span :if={@sun_window != nil} class="kw-w-chip">
            <span class="kw-w-chip-icon" aria-hidden="true">🌅</span>{@sun_window}
          </span>
        </div>

        <div :if={@hourly != []} class="kw-w-hourly">
          <div :for={h <- @hourly} class="kw-w-hourly-cell">
            <div class="kw-w-hourly-time">{h.label}</div>
            <div class="kw-w-hourly-icon"><.weather_icon scene={h.scene} small /></div>
            <div class="kw-w-hourly-temp">{h.temp}</div>
          </div>
        </div>

        <div :if={@daily != []} class="kw-w-daily">
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
          <path class="kw-w-moon" d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z" fill="currentColor" fill-opacity="0.85" />
        <% "partly" -> %>
          <path d="M12 2v2" />
          <path d="m4.93 4.93 1.41 1.41" />
          <path d="M20 12h2" />
          <path d="m19.07 4.93-1.41 1.41" />
          <path d="M15.947 12.65a4 4 0 0 0-5.925-4.128" />
          <path class="kw-w-cloud" d="M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6Z" />
        <% "cloudy" -> %>
          <path class="kw-w-cloud" d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
        <% "fog" -> %>
          <path d="M16 17H7a5 5 0 1 1 4.9-6H17a3 3 0 0 1 0 6h-1" />
          <g class="kw-w-fog-lines">
            <path d="M16 21H7" />
            <path d="M19 21h-3" />
            <path d="M11 13H3" />
          </g>
        <% "drizzle" -> %>
          <path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
          <g class="kw-w-rain">
            <path d="M8 19v1" />
            <path d="M8 14v1" />
            <path d="M16 19v1" />
            <path d="M16 14v1" />
            <path d="M12 21v1" />
            <path d="M12 16v1" />
          </g>
        <% s when s in ["rain", "showers"] -> %>
          <path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
          <g class="kw-w-rain">
            <path d="M16 14v6" />
            <path d="M8 14v6" />
            <path d="M12 16v6" />
          </g>
        <% "snow" -> %>
          <path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
          <g class="kw-w-snow">
            <path d="M8 15h.01" />
            <path d="M8 19h.01" />
            <path d="M12 17h.01" />
            <path d="M12 21h.01" />
            <path d="M16 15h.01" />
            <path d="M16 19h.01" />
          </g>
        <% "thunder" -> %>
          <path d="M6 16.326A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 .5 8.973" />
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

  defp daily_today(%{"time" => [date | _]} = daily) do
    %{
      "date" => date,
      "max" => List.first(daily["temperature_2m_max"] || []),
      "min" => List.first(daily["temperature_2m_min"] || []),
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

  defp format_hour_label(
         <<_y::binary-size(4), "-", _m::binary-size(2), "-", _d::binary-size(2), "T",
           hh::binary-size(2), ":", _mm::binary-size(2), _rest::binary>>
       ) do
    "#{hh}:00"
  end

  defp format_hour_label(_), do: ""

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
