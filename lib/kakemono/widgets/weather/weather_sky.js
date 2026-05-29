// WeatherSky — keeps the weather widget's sky in sync with the location's
// local time. Reads data-latitude / data-longitude / data-utc-offset (seconds)
// from the widget root and sets data-tod="dawn|day|dusk|night" so the CSS can
// tint the scene (warm dawn/dusk, darker night) independently of the cached
// weather scene. Reuses the NOAA sun-time math from the clock widget.

import {
  moonPosition,
  sunPosition,
  sunTimes,
  timeOfDay,
  tzOffsetMinutes,
} from "../clock/clock_tick.js";

const RAD = Math.PI / 180;
const MS_PER_DAY = 86400_000;

function clamp01(value) {
  if (!Number.isFinite(value)) return 0;
  return Math.min(1, Math.max(0, value));
}

function twilightStrength(hour, sunrise, sunset) {
  return Math.max(
    clamp01(1 - Math.abs(hour - sunrise) / 1.5),
    clamp01(1 - Math.abs(hour - sunset) / 1.5),
  );
}

function nightStrength(hour, sunrise, sunset, tod) {
  if (tod === "night") return 1;
  if (tod === "dusk") return clamp01((hour - (sunset - 1)) / 2);
  if (tod === "dawn") return clamp01(((sunrise + 1) - hour) / 2);
  return 0;
}

function solarAltitude(localDate, hour, lat, lon, offsetMin) {
  const localDay = Date.UTC(
    localDate.getUTCFullYear(),
    localDate.getUTCMonth(),
    localDate.getUTCDate(),
  );
  const start = Date.UTC(localDate.getUTCFullYear(), 0, 0);
  const dayOfYear = Math.floor((localDay - start) / MS_PER_DAY);

  const g = ((2 * Math.PI) / 365) * (dayOfYear - 1 + (hour - 12) / 24);
  const eqtime =
    229.18 *
    (0.000075 +
      0.001868 * Math.cos(g) -
      0.032077 * Math.sin(g) -
      0.014615 * Math.cos(2 * g) -
      0.040849 * Math.sin(2 * g));

  const decl =
    0.006918 -
    0.399912 * Math.cos(g) +
    0.070257 * Math.sin(g) -
    0.006758 * Math.cos(2 * g) +
    0.000907 * Math.sin(2 * g) -
    0.002697 * Math.cos(3 * g) +
    0.00148 * Math.sin(3 * g);

  let trueSolarMin = (hour * 60 + eqtime + 4 * lon - offsetMin) % 1440;
  if (trueSolarMin < 0) trueSolarMin += 1440;

  let hourAngle = trueSolarMin / 4 - 180;
  if (hourAngle < -180) hourAngle += 360;

  const latR = lat * RAD;
  const haR = hourAngle * RAD;
  const altR = Math.asin(
    Math.sin(latR) * Math.sin(decl) +
      Math.cos(latR) * Math.cos(decl) * Math.cos(haR),
  );
  return altR / RAD;
}

function starStrengthFromSolarAltitude(altitude) {
  // Stars start to read after civil twilight and reach full strength near
  // astronomical darkness. This keeps late-sunset locations twilight-lit.
  const raw = clamp01((-altitude - 6) / 12);
  return raw * raw * (3 - 2 * raw);
}

function polarTwilightStrength(altitude) {
  return clamp01((altitude + 12) / 12);
}

function setSkyVars(el, sun, moon, twilight, night, stars) {
  const style = el.style;
  style.setProperty("--sun-x", sun.x.toFixed(4));
  style.setProperty("--sun-y", sun.y.toFixed(4));
  style.setProperty("--sun-visible", String(sun.visible));
  style.setProperty("--moon-x", moon.x.toFixed(4));
  style.setProperty("--moon-y", moon.y.toFixed(4));
  style.setProperty("--moon-visible", String(moon.visible));
  style.setProperty("--twilight-strength", twilight.toFixed(4));
  style.setProperty("--night-strength", night.toFixed(4));
  style.setProperty("--star-strength", stars.toFixed(4));
}

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

    let tod, sun, moon, twilight, night, stars;
    if (hasLocation) {
      const st = sunTimes(now, lat, lon, offsetMin);
      const altitude = solarAltitude(d, hourFrac, lat, lon, offsetMin);
      stars = starStrengthFromSolarAltitude(altitude);
      if (st.polarDay) {
        tod = "day";
        sun = sunPosition(hourFrac, 0, 24);
        moon = { x: 0, y: 0, visible: 0 };
        twilight = 0;
        night = 0;
        stars = 0;
      } else if (st.polarNight) {
        tod = "night";
        sun = { x: 0, y: 0, visible: 0 };
        moon = { x: hourFrac / 24, y: Math.sin(Math.PI * (hourFrac / 24)), visible: 1 };
        twilight = polarTwilightStrength(altitude);
        night = 1;
      } else {
        tod = timeOfDay(hourFrac, st.sunrise, st.sunset);
        sun = sunPosition(hourFrac, st.sunrise, st.sunset);
        moon = moonPosition(hourFrac, st.sunset, st.sunrise);
        twilight = twilightStrength(hourFrac, st.sunrise, st.sunset);
        night = nightStrength(hourFrac, st.sunrise, st.sunset, tod);
      }
    } else {
      tod = timeOfDay(hourFrac);
      sun = sunPosition(hourFrac);
      moon = moonPosition(hourFrac);
      twilight = twilightStrength(hourFrac, 6, 18);
      night = nightStrength(hourFrac, 6, 18, tod);
      stars = night;
    }

    setSkyVars(el, sun, moon, twilight, night, stars);

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
