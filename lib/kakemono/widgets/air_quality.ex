defmodule Kakemono.Widgets.AirQuality do
  @moduledoc """
  Air Quality widget: displays current AQI, PM2.5/PM10 levels, and pollen counts.
  Uses Open-Meteo's free Air Quality API.

  Config:
    * `latitude`  (required, number) — location latitude
    * `longitude` (required, number) — location longitude
    * `label`     (optional, string) — display name for location
    * `cached`    (internal, map) — API response cache
  """

  @behaviour Kakemono.Widget
  use Phoenix.Component

  @impl true
  def type, do: "air_quality"

  @impl true
  def name, do: "Air Quality"

  @impl true
  def config_schema do
    %{
      "type" => "object",
      "required" => ["latitude", "longitude"],
      "properties" => %{
        "latitude" => %{"type" => "number", "minimum" => -90, "maximum" => 90},
        "longitude" => %{"type" => "number", "minimum" => -180, "maximum" => 180},
        "label" => %{"type" => "string"},
        "cached" => %{"type" => "object"}
      },
      "additionalProperties" => false
    }
  end

  @impl true
  def default_config do
    %{"latitude" => 0.0, "longitude" => 0.0, "label" => "Air Quality"}
  end

  @impl true
  def draft_config, do: %{}

  @impl true
  def config_fields do
    [
      %{
        key: "label",
        label: "Location",
        type: :location_search,
        required: true,
        placeholder: "Search a city…"
      },
      %{key: "latitude", type: :number, hidden: true, required: true, step: "any"},
      %{key: "longitude", type: :number, hidden: true, required: true, step: "any"}
    ]
  end

  @impl true
  def prefetch(%Kakemono.Widgets.Instance{id: id, config: cfg}) do
    cached = cfg["cached"]
    lat = cfg["latitude"]
    lon = cfg["longitude"]
    has_location? = is_number(lat) and is_number(lon) and not (lat == 0.0 and lon == 0.0)
    empty? = is_nil(cached) or cached == %{}

    if has_location? and empty? do
      %{instance_id: id}
      |> Kakemono.Widgets.AirQualityFetchWorker.new()
      |> Oban.insert!()
    end

    :ok
  end

  def open_meteo_url(lat, lon) do
    "https://air-quality-api.open-meteo.com/v1/air-quality" <>
      "?latitude=#{lat}&longitude=#{lon}" <>
      "&current=european_aqi,pm10,pm2_5,grass_pollen,birch_pollen,ragweed_pollen" <>
      "&timezone=auto"
  end

  @impl true
  def render(assigns) do
    cfg = assigns.instance.config
    cached = cfg["cached"] || %{}
    current = cached["current"] || %{}

    aqi = current["european_aqi"]
    {aqi_level, aqi_label} = aqi_classification(aqi)

    grass_pollen = pollen_level(current["grass_pollen"])
    tree_pollen = pollen_level(current["birch_pollen"])
    ragweed_pollen = pollen_level(current["ragweed_pollen"])
    pollen_severity = compute_pollen_severity(grass_pollen, tree_pollen, ragweed_pollen)

    assigns =
      Map.merge(assigns, %{
        label: cfg["label"] || "Air Quality",
        aqi: aqi,
        aqi_level: aqi_level,
        aqi_label: aqi_label,
        pm25: current["pm2_5"],
        pm10: current["pm10"],
        grass_pollen: grass_pollen,
        tree_pollen: tree_pollen,
        ragweed_pollen: ragweed_pollen,
        pollen_severity: pollen_severity
      })

    ~H"""
    <div class={"kakemono-widget kakemono-widget-air-quality"} data-aqi={@aqi_level} data-pollen={@pollen_severity}>
      <.pollen_field />
      <div class="kw-aq-content">
        <div class="kw-aq-header">
          <span class="kw-aq-eyebrow">Air Quality</span>
          <span :if={@label != "Air Quality"} class="kw-aq-loc">{@label}</span>
        </div>

        <div :if={is_nil(@aqi)} class="kw-aq-empty">
          Waiting for data…
        </div>

        <div :if={not is_nil(@aqi)} class="kw-aq-hero">
          <div class="kw-aq-hero-icon">
            <.aqi_icon level={@aqi_level} />
          </div>
          <div class="kw-aq-hero-text">
            <div class="kw-aq-value">{@aqi}</div>
            <div class="kw-aq-label">{@aqi_label}</div>
            <div class="kw-aq-caption">Air Quality Index</div>
          </div>
        </div>

        <div :if={not is_nil(@pm25) or not is_nil(@pm10)} class="kw-aq-chips">
          <span :if={not is_nil(@pm25)} class="kw-aq-chip">
            <span class="kw-aq-chip-name">Fine dust</span>
            <span class="kw-aq-chip-abbr">PM2.5</span>
            <span class="kw-aq-chip-value">
              {format_number(@pm25)}<span class="kw-aq-chip-unit">µg/m³</span>
            </span>
          </span>
          <span :if={not is_nil(@pm10)} class="kw-aq-chip">
            <span class="kw-aq-chip-name">Coarse dust</span>
            <span class="kw-aq-chip-abbr">PM10</span>
            <span class="kw-aq-chip-value">
              {format_number(@pm10)}<span class="kw-aq-chip-unit">µg/m³</span>
            </span>
          </span>
        </div>

        <div :if={has_pollen?(@grass_pollen, @tree_pollen, @ragweed_pollen)} class="kw-aq-pollen">
          <div :if={@grass_pollen} class={"kw-aq-pollen-row"} data-level={@grass_pollen.level}>
            <.pollen_icon type="grass" />
            <span class="kw-aq-pollen-type">Grass</span>
            <span class="kw-aq-pollen-value">{@grass_pollen.label}</span>
          </div>
          <div :if={@tree_pollen} class={"kw-aq-pollen-row"} data-level={@tree_pollen.level}>
            <.pollen_icon type="tree" />
            <span class="kw-aq-pollen-type">Tree</span>
            <span class="kw-aq-pollen-value">{@tree_pollen.label}</span>
          </div>
          <div :if={@ragweed_pollen} class={"kw-aq-pollen-row"} data-level={@ragweed_pollen.level}>
            <.pollen_icon type="ragweed" />
            <span class="kw-aq-pollen-type">Ragweed</span>
            <span class="kw-aq-pollen-value">{@ragweed_pollen.label}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :level, :string, required: true

  defp aqi_icon(assigns) do
    ~H"""
    <svg class="kw-aq-icon" viewBox="0 0 24 24" aria-hidden="true">
      <%= case @level do %>
        <% "good" -> %>
          <circle cx="12" cy="12" r="10" />
          <path d="m9 12 2 2 4-4" />
        <% "fair" -> %>
          <circle cx="12" cy="12" r="10" />
          <path d="M8 12h8" />
        <% "moderate" -> %>
          <circle cx="12" cy="12" r="10" />
          <path d="M12 8v4" />
          <circle cx="12" cy="16" r="0.5" fill="currentColor" />
        <% "poor" -> %>
          <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
          <path d="M12 9v4" />
          <circle cx="12" cy="17" r="0.5" fill="currentColor" />
        <% "very-poor" -> %>
          <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
          <path d="M12 9v4" />
          <circle cx="12" cy="17" r="0.5" fill="currentColor" />
        <% "hazardous" -> %>
          <circle cx="12" cy="12" r="10" />
          <path d="m15 9-6 6" />
          <path d="m9 9 6 6" />
        <% _ -> %>
          <circle cx="12" cy="12" r="10" />
          <path d="M12 16v.01" />
          <path d="M12 8v4" />
      <% end %>
    </svg>
    """
  end

  defp pollen_field(assigns) do
    ~H"""
    <div class="kw-aq-pollen-field" aria-hidden="true">
      <svg class="kw-aq-particles" viewBox="0 0 100 100" preserveAspectRatio="none">
        <circle class="kw-aq-particle kw-aq-particle-lg" cx="12" cy="18" r="1.8" style="--delay: 0s; --drift: 15px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="28" cy="42" r="0.9" style="--delay: 2.1s; --drift: -12px;" />
        <circle class="kw-aq-particle kw-aq-particle-md" cx="45" cy="8" r="1.3" style="--delay: 4.5s; --drift: 18px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="62" cy="55" r="0.8" style="--delay: 1.2s; --drift: -8px;" />
        <circle class="kw-aq-particle kw-aq-particle-lg" cx="78" cy="25" r="1.6" style="--delay: 3.8s; --drift: 20px;" />
        <circle class="kw-aq-particle kw-aq-particle-md" cx="88" cy="68" r="1.2" style="--delay: 0.6s; --drift: -15px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="8" cy="72" r="0.7" style="--delay: 5.2s; --drift: 10px;" />
        <circle class="kw-aq-particle kw-aq-particle-md" cx="35" cy="85" r="1.1" style="--delay: 2.8s; --drift: -18px;" />
        <circle class="kw-aq-particle kw-aq-particle-lg" cx="55" cy="35" r="1.5" style="--delay: 4.0s; --drift: 14px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="72" cy="78" r="0.6" style="--delay: 1.8s; --drift: -10px;" />
        <circle class="kw-aq-particle kw-aq-particle-md" cx="92" cy="12" r="1.0" style="--delay: 3.2s; --drift: 16px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="18" cy="52" r="0.8" style="--delay: 0.3s; --drift: -14px;" />
        <circle class="kw-aq-particle kw-aq-particle-lg" cx="42" cy="62" r="1.4" style="--delay: 5.8s; --drift: 12px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="68" cy="5" r="0.7" style="--delay: 2.5s; --drift: -16px;" />
        <circle class="kw-aq-particle kw-aq-particle-md" cx="85" cy="45" r="1.2" style="--delay: 4.2s; --drift: 8px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="5" cy="32" r="0.9" style="--delay: 1.5s; --drift: -20px;" />
        <circle class="kw-aq-particle kw-aq-particle-lg" cx="25" cy="92" r="1.7" style="--delay: 3.5s; --drift: 22px;" />
        <circle class="kw-aq-particle kw-aq-particle-md" cx="58" cy="88" r="1.0" style="--delay: 0.9s; --drift: -12px;" />
        <circle class="kw-aq-particle kw-aq-particle-sm" cx="82" cy="92" r="0.6" style="--delay: 6.0s; --drift: 10px;" />
        <circle class="kw-aq-particle kw-aq-particle-md" cx="48" cy="48" r="1.1" style="--delay: 2.2s; --drift: -8px;" />
      </svg>
    </div>
    """
  end

  attr :type, :string, required: true

  defp pollen_icon(assigns) do
    ~H"""
    <svg class="kw-aq-pollen-icon" viewBox="0 0 24 24" aria-hidden="true">
      <%= case @type do %>
        <% "grass" -> %>
          <path d="M12 10a7 7 0 0 0-7 7v5h14v-5a7 7 0 0 0-7-7Z" />
          <path d="M12 2v8" />
          <path d="M8 6c1 0 2 1 4 1s3-1 4-1" />
        <% "tree" -> %>
          <path d="M12 22v-7" />
          <path d="M9 22h6" />
          <path d="M12 3C8.13 3 5 6.13 5 10c0 2.76 1.12 4.5 3 5.5V15l4 1 4-1v.5c1.88-1 3-2.74 3-5.5 0-3.87-3.13-7-7-7Z" />
        <% "ragweed" -> %>
          <path d="M12 22V9" />
          <path d="M7 12c2-2 4-2 5-2s3 0 5 2" />
          <path d="M6 17c2-2 5-2 6-2s4 0 6 2" />
          <path d="M12 9c0-3 1-5 3-7" />
          <path d="M12 9c0-3-1-5-3-7" />
        <% _ -> %>
          <circle cx="12" cy="12" r="8" />
      <% end %>
    </svg>
    """
  end

  defp aqi_classification(aqi) when is_number(aqi) do
    cond do
      aqi <= 20 -> {"good", "Good"}
      aqi <= 40 -> {"fair", "Fair"}
      aqi <= 60 -> {"moderate", "Moderate"}
      aqi <= 80 -> {"poor", "Poor"}
      aqi <= 100 -> {"very-poor", "Very Poor"}
      true -> {"hazardous", "Hazardous"}
    end
  end

  defp aqi_classification(_), do: {"unknown", "—"}

  defp pollen_level(value) when is_number(value) and value > 0 do
    {level, label} =
      cond do
        value < 10 -> {"low", "Low"}
        value < 50 -> {"moderate", "Moderate"}
        value < 100 -> {"high", "High"}
        true -> {"very-high", "Very High"}
      end

    %{level: level, label: label, value: value}
  end

  defp pollen_level(_), do: nil

  defp has_pollen?(grass, tree, ragweed) do
    not is_nil(grass) or not is_nil(tree) or not is_nil(ragweed)
  end

  defp compute_pollen_severity(grass, tree, ragweed) do
    levels = [grass, tree, ragweed] |> Enum.reject(&is_nil/1) |> Enum.map(& &1.level)

    cond do
      "very-high" in levels -> "very-high"
      "high" in levels -> "high"
      "moderate" in levels -> "moderate"
      "low" in levels -> "low"
      true -> "none"
    end
  end

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(_), do: "—"
end
