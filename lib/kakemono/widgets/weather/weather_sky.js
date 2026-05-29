// WeatherSky — keeps the weather widget's sky in sync with the location's
// local time. Reads data-latitude / data-longitude / data-utc-offset (seconds)
// from the widget root and sets data-tod="dawn|day|dusk|night" so the CSS can
// tint the scene (warm dawn/dusk, darker night) independently of the cached
// weather scene. Reuses the NOAA sun-time math from the clock widget.

import { sunTimes, timeOfDay, tzOffsetMinutes } from "../clock/clock_tick.js";

const WeatherSky = {
  mounted() { this.start(); },
  updated() { this.stop(); this.start(); },
  destroyed() { this.stop(); },

  start() {
    this.render();
    // The sky changes slowly; once a minute is plenty and cheap.
    this.timer = setInterval(() => this.render(), 60_000);
  },

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  },

  render() {
    const el = this.el;
    const lat = Number.parseFloat(el.dataset.latitude);
    const lon = Number.parseFloat(el.dataset.longitude);
    const hasLocation =
      Number.isFinite(lat) && Number.isFinite(lon) && !(lat === 0 && lon === 0);

    const now = new Date();

    // Offset of the location's clock from UTC, in minutes. Open-Meteo gives it
    // in seconds; fall back to the configured timezone, then the host offset.
    const tz = el.dataset.timezone || undefined;
    const rawOffset = el.dataset.utcOffset;
    const offsetSec = Number.parseInt(rawOffset, 10);
    const offsetMin = rawOffset !== undefined && rawOffset !== "" && Number.isFinite(offsetSec)
      ? offsetSec / 60
      : tzOffsetMinutes(now, tz);

    // Current wall-clock hour at the location.
    const localMs = now.getTime() + offsetMin * 60_000;
    const d = new Date(localMs);
    const hourFrac =
      d.getUTCHours() + d.getUTCMinutes() / 60 + d.getUTCSeconds() / 3600;

    let tod;
    if (hasLocation) {
      const st = sunTimes(now, lat, lon, offsetMin);
      if (st.polarDay) tod = "day";
      else if (st.polarNight) tod = "night";
      else tod = timeOfDay(hourFrac, st.sunrise, st.sunset);
    } else {
      tod = timeOfDay(hourFrac);
    }

    const isDay = tod === "night" ? "0" : "1";
    if (el.getAttribute("data-tod") !== tod) {
      el.setAttribute("data-tod", tod);
    }
    // Keep data-is-day consistent with the live sky (dawn/day/dusk are day-ish).
    if (el.getAttribute("data-is-day") !== isDay) {
      el.setAttribute("data-is-day", isDay);
    }
    this.lastTod = tod;
  },
};

export default WeatherSky;
