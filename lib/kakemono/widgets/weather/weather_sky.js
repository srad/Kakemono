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
    // in seconds; fall back to the host's offset when it is missing.
    const offsetSec = Number.parseInt(el.dataset.utcOffset, 10);
    const offsetMin = Number.isFinite(offsetSec)
      ? offsetSec / 60
      : tzOffsetMinutes(now);

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

    if (this.lastTod !== tod) {
      el.setAttribute("data-tod", tod);
      this.lastTod = tod;
    }
  },
};

export default WeatherSky;
