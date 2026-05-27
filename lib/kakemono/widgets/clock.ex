defmodule Kakemono.Widgets.Clock do
  @behaviour Kakemono.Widget
  use Phoenix.Component

  @styles ~w(celestial lunar minimal)

  @impl true
  def type, do: "clock"

  @impl true
  def name, do: "Clock"

  @impl true
  def config_schema do
    %{
      "type" => "object",
      "properties" => %{
        "style" => %{"type" => "string", "enum" => @styles},
        "format" => %{"type" => "string", "enum" => ["24h", "12h"]},
        "show_seconds" => %{"type" => "boolean"},
        "timezone" => %{"type" => "string"}
      },
      "additionalProperties" => false
    }
  end

  @impl true
  def default_config do
    %{
      "style" => "celestial",
      "format" => "24h",
      "show_seconds" => false,
      "timezone" => "Etc/UTC"
    }
  end

  @impl true
  def config_fields do
    [
      %{
        key: "style",
        label: "Style",
        type: :select,
        required: false,
        options: [
          {"celestial", "Celestial"},
          {"lunar", "Lunar"},
          {"minimal", "Minimal"}
        ]
      },
      %{key: "timezone", label: "Timezone", type: :text, required: false, placeholder: "Etc/UTC"},
      %{
        key: "format",
        label: "Format",
        type: :select,
        required: false,
        options: [{"24h", "24h"}, {"12h", "12h"}]
      },
      %{key: "show_seconds", label: "Show seconds", type: :checkbox, required: false}
    ]
  end

  @impl true
  def render(assigns) do
    style = Map.get(assigns.instance.config, "style", "celestial")
    style = if style in @styles, do: style, else: "celestial"

    assigns =
      assigns
      |> Map.put(:style, style)
      |> Map.put(:format, Map.get(assigns.instance.config, "format", "24h"))
      |> Map.put(:show_seconds, Map.get(assigns.instance.config, "show_seconds", false))
      |> Map.put(:timezone, Map.get(assigns.instance.config, "timezone", "Etc/UTC"))
      |> Map.put(:clock_id, "clock-" <> Integer.to_string(assigns.instance.id))

    ~H"""
    <div
      class={"kakemono-widget kakemono-widget-clock " <> style_class(@style)}
      data-style={@style}
      data-tod="night"
    >
      <%= case @style do %>
        <% "celestial" -> %>
          <div class="kw-clock-scene" aria-hidden="true">
            <div class="kw-clock-sky"></div>
            <.star_field />
            <.cloud_field />
            <div class="kw-clock-sun-wrap">
              <div class="kw-clock-halo kw-clock-halo-sun"></div>
              <.sun_svg size="hero" />
            </div>
            <div class="kw-clock-moon-wrap">
              <div class="kw-clock-halo kw-clock-halo-moon"></div>
              <.moon_svg />
            </div>
            <div class="kw-clock-horizon"></div>
          </div>
          <div class="kw-clock-stack kw-clock-stack-celestial">
            <time
              phx-hook="ClockTick"
              id={@clock_id}
              data-style={@style}
              data-format={@format}
              data-show-seconds={to_string(@show_seconds)}
              data-timezone={@timezone}
              class="kw-clock-time"
            >
              --:--
            </time>
            <div data-clock-date class="kw-clock-date"></div>
          </div>
        <% "lunar" -> %>
          <div class="kw-clock-scene" aria-hidden="true">
            <div class="kw-clock-sky"></div>
            <.star_field />
            <div class="kw-clock-focal">
              <div class="kw-clock-halo kw-clock-halo-focal"></div>
              <div class="kw-clock-focal-sun" data-show-when="day">
                <.sun_svg size="large" />
              </div>
              <div class="kw-clock-focal-moon" data-show-when="night">
                <.moon_svg />
              </div>
            </div>
          </div>
          <div class="kw-clock-stack kw-clock-stack-lunar">
            <time
              phx-hook="ClockTick"
              id={@clock_id}
              data-style={@style}
              data-format={@format}
              data-show-seconds={to_string(@show_seconds)}
              data-timezone={@timezone}
              class="kw-clock-time"
            >
              --:--
            </time>
            <div data-clock-date class="kw-clock-date"></div>
          </div>
        <% "minimal" -> %>
          <div class="kw-clock-stack kw-clock-stack-minimal">
            <div data-clock-weekday class="kw-clock-weekday"></div>
            <time
              phx-hook="ClockTick"
              id={@clock_id}
              data-style={@style}
              data-format={@format}
              data-show-seconds={to_string(@show_seconds)}
              data-timezone={@timezone}
              class="kw-clock-time"
            >
              --:--
            </time>
            <div class="kw-clock-meta">
              <div data-clock-date class="kw-clock-date-pill"></div>
              <%= if @show_seconds do %>
                <div class="kw-clock-progress" aria-hidden="true"></div>
              <% end %>
            </div>
            <div class="kw-clock-badge" aria-hidden="true">
              <div class="kw-clock-badge-sun"><.sun_svg size="badge" /></div>
              <div class="kw-clock-badge-moon"><.moon_svg /></div>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  defp style_class("lunar"), do: "kw-clock-style-lunar"
  defp style_class("minimal"), do: "kw-clock-style-minimal"
  defp style_class(_), do: "kw-clock-style-celestial"

  # ── SVG motif components ────────────────────────────────────────

  attr :size, :string, default: "hero"

  # Sun — Lucide-inspired but richer: two counter-rotating ray fans
  # (8 long + 8 short), a filled core with glow ring and a specular
  # highlight. Color comes from CSS `color` (Lucide convention).
  defp sun_svg(assigns) do
    ~H"""
    <svg
      class={["kw-clock-sun", "kw-clock-sun-" <> @size]}
      viewBox="0 0 200 200"
      aria-hidden="true"
    >
      <g class="kw-sun-rays kw-sun-rays-long">
        <line x1="150" y1="100" x2="192" y2="100" />
        <line x1="135.4" y1="135.4" x2="165.0" y2="165.0" />
        <line x1="100" y1="150" x2="100" y2="192" />
        <line x1="64.6" y1="135.4" x2="35.0" y2="165.0" />
        <line x1="50" y1="100" x2="8" y2="100" />
        <line x1="64.6" y1="64.6" x2="35.0" y2="35.0" />
        <line x1="100" y1="50" x2="100" y2="8" />
        <line x1="135.4" y1="64.6" x2="165.0" y2="35.0" />
      </g>
      <g class="kw-sun-rays kw-sun-rays-short">
        <line x1="146.2" y1="119.1" x2="164.7" y2="126.8" />
        <line x1="119.1" y1="146.2" x2="126.8" y2="164.7" />
        <line x1="80.9" y1="146.2" x2="73.2" y2="164.7" />
        <line x1="53.8" y1="119.1" x2="35.3" y2="126.8" />
        <line x1="53.8" y1="80.9" x2="35.3" y2="73.2" />
        <line x1="80.9" y1="53.8" x2="73.2" y2="35.3" />
        <line x1="119.1" y1="53.8" x2="126.8" y2="35.3" />
        <line x1="146.2" y1="80.9" x2="164.7" y2="73.2" />
      </g>
      <circle class="kw-sun-glow" cx="100" cy="100" r="48" />
      <circle class="kw-sun-core" cx="100" cy="100" r="36" />
      <circle class="kw-sun-spec" cx="88" cy="86" r="11" />
    </svg>
    """
  end

  # Moon — full lit base disc + left-hemisphere unlit overlay + a
  # scaleX-animated terminator ellipse that produces gibbous/crescent
  # phases. The whole body is mirrored on the X axis via CSS when the
  # moon is waning so the same waxing-oriented SVG describes both halves
  # of the cycle.
  defp moon_svg(assigns) do
    ~H"""
    <svg class="kw-clock-moon" viewBox="0 0 200 200" aria-hidden="true">
      <g class="kw-moon-body">
        <circle class="kw-moon-lit" cx="100" cy="100" r="80" />
        <g class="kw-moon-craters">
          <circle cx="138" cy="78" r="9" />
          <circle cx="148" cy="118" r="6" />
          <circle cx="124" cy="138" r="11" />
          <circle cx="116" cy="92" r="5" />
        </g>
        <path
          class="kw-moon-shadow"
          d="M 100,20 A 80,80 0 0 0 100,180 Z"
        />
        <ellipse class="kw-moon-terminator" cx="100" cy="100" rx="80" ry="80" />
        <circle class="kw-moon-rim" cx="100" cy="100" r="79" />
      </g>
    </svg>
    """
  end

  # 14 stars at hand-picked positions across the sky. Each gets a
  # CSS animation-delay set inline so twinkling stays organic.
  defp star_field(assigns) do
    ~H"""
    <svg class="kw-clock-stars" viewBox="0 0 200 100" preserveAspectRatio="none" aria-hidden="true">
      <g>
        <.star x="8" y="14" delay="0.0" />
        <.star x="22" y="9" delay="1.4" />
        <.star x="36" y="20" delay="0.6" />
        <.star x="48" y="11" delay="2.2" />
        <.star x="62" y="25" delay="1.8" />
        <.star x="76" y="14" delay="0.9" />
        <.star x="89" y="6" delay="2.6" />
        <.star x="104" y="22" delay="1.1" />
        <.star x="120" y="12" delay="0.3" />
        <.star x="138" y="28" delay="2.0" />
        <.star x="154" y="9" delay="1.5" />
        <.star x="168" y="18" delay="0.7" />
        <.star x="182" y="6" delay="2.4" />
        <.star x="192" y="22" delay="1.3" />
      </g>
    </svg>
    """
  end

  attr :x, :string, required: true
  attr :y, :string, required: true
  attr :delay, :string, required: true

  defp star(assigns) do
    ~H"""
    <path
      class="kw-clock-star"
      style={"animation-delay: " <> @delay <> "s;"}
      transform={"translate(" <> @x <> " " <> @y <> ")"}
      d="M 0,-3 L 0.6,-0.6 L 3,0 L 0.6,0.6 L 0,3 L -0.6,0.6 L -3,0 L -0.6,-0.6 Z"
    />
    """
  end

  # Cloud container — clouds are rendered dynamically by the ClockTick JS hook
  defp cloud_field(assigns) do
    ~H"""
    <div class="kw-clock-clouds" aria-hidden="true"></div>
    """
  end
end
