// ClockTick — updates a <time> element every second.
// Reads data-format ("24h"|"12h"), data-show-seconds ("true"|"false"), data-timezone (IANA),
// data-style ("celestial"|"lunar"|"minimal") and publishes clock CSS vars for the
// surrounding widget element so the celestial motifs can move with the clock.

const SYNODIC_DAYS = 29.530588853;
// 2000-01-06T18:14Z — a well-known new moon used as the epoch for the cycle.
const NEW_MOON_EPOCH_MS = Date.UTC(2000, 0, 6, 18, 14, 0);
const MS_PER_DAY = 86400_000;

// Pure functions — exported so they can be unit-tested without a DOM.

export function moonPhase(date) {
  const days = (date.getTime() - NEW_MOON_EPOCH_MS) / MS_PER_DAY;
  let phase = (days % SYNODIC_DAYS) / SYNODIC_DAYS;
  if (phase < 0) phase += 1;
  return phase;
}

const RAD = Math.PI / 180;

// Sunrise/sunset for a location, as fractional local clock hours.
// Implements the NOAA sunrise equation (declination + equation of time + hour
// angle at the 90.833° zenith that accounts for atmospheric refraction).
//   lat, lon  — degrees, longitude positive East (Open-Meteo convention)
//   tzOffsetMin — minutes the location's clock is ahead of UTC (local − UTC)
// Returns { sunrise, sunset } in hours, or { polarDay } / { polarNight } when
// the sun stays above / below the horizon for the whole day.
export function sunTimes(date, lat, lon, tzOffsetMin) {
  const start = Date.UTC(date.getUTCFullYear(), 0, 0);
  const dayOfYear = Math.floor((date.getTime() - start) / MS_PER_DAY);

  // Fractional year (radians).
  const g = ((2 * Math.PI) / 365) * (dayOfYear - 1);

  // Equation of time (minutes).
  const eqtime =
    229.18 *
    (0.000075 +
      0.001868 * Math.cos(g) -
      0.032077 * Math.sin(g) -
      0.014615 * Math.cos(2 * g) -
      0.040849 * Math.sin(2 * g));

  // Solar declination (radians).
  const decl =
    0.006918 -
    0.399912 * Math.cos(g) +
    0.070257 * Math.sin(g) -
    0.006758 * Math.cos(2 * g) +
    0.000907 * Math.sin(2 * g) -
    0.002697 * Math.cos(3 * g) +
    0.00148 * Math.sin(3 * g);

  const latR = lat * RAD;
  const cosHa =
    Math.cos(90.833 * RAD) / (Math.cos(latR) * Math.cos(decl)) -
    Math.tan(latR) * Math.tan(decl);

  if (cosHa < -1) return { polarDay: true };
  if (cosHa > 1) return { polarNight: true };

  const haDeg = Math.acos(cosHa) / RAD;

  // Minutes from UTC midnight, then shifted into the location's local clock.
  const solarNoonUtc = 720 - 4 * lon - eqtime;
  const sunriseMin = solarNoonUtc - 4 * haDeg + tzOffsetMin;
  const sunsetMin = solarNoonUtc + 4 * haDeg + tzOffsetMin;

  return { sunrise: sunriseMin / 60, sunset: sunsetMin / 60 };
}

// Minutes the IANA timezone `tz` is ahead of UTC for the given instant.
// Falls back to the host's local offset when `tz` is absent/invalid.
export function tzOffsetMinutes(date, tz) {
  if (!tz) return -date.getTimezoneOffset();
  try {
    const parts = {};
    new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hour12: false,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    })
      .formatToParts(date)
      .forEach((p) => (parts[p.type] = p.value));

    const asUtc = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour) % 24,
      Number(parts.minute),
      Number(parts.second),
    );
    return Math.round((asUtc - date.getTime()) / 60000);
  } catch (_e) {
    return -date.getTimezoneOffset();
  }
}

// Parabolic arc across the daylight window. Returns {x, y, visible}, x,y in [0,1].
// Defaults to a fixed 6:00 → 18:00 window when no location is configured.
export function sunPosition(hour, sunrise = 6, sunset = 18) {
  const t = (hour - sunrise) / (sunset - sunrise);
  if (t < 0 || t > 1) return { x: 0, y: 0, visible: 0 };
  return { x: t, y: Math.sin(Math.PI * t), visible: 1 };
}

// Parabolic arc across the night window [sunset → next sunrise]. The moon owns
// the night: it rises at the real sunset and sets at the next sunrise.
export function moonPosition(hour, sunset = 18, sunrise = 6) {
  const nightLength = sunrise + 24 - sunset;
  let t;
  if (hour >= sunset) t = (hour - sunset) / nightLength;
  else if (hour < sunrise) t = (hour + 24 - sunset) / nightLength;
  else return { x: 0, y: 0, visible: 0 };
  return { x: t, y: Math.sin(Math.PI * t), visible: 1 };
}

// dawn/dusk are ±1h bands around sunrise/sunset; day between, night otherwise.
// Defaults to the fixed 6:00 → 18:00 window when no location is configured.
export function timeOfDay(hour, sunrise = 6, sunset = 18) {
  if (hour >= sunrise - 1 && hour < sunrise + 1) return "dawn";
  if (hour >= sunrise + 1 && hour < sunset - 1) return "day";
  if (hour >= sunset - 1 && hour < sunset + 1) return "dusk";
  return "night";
}

// Generate fluffy cloud shape using arc-based outline (cccloud technique)
// Creates natural puffy cloud silhouettes by connecting points with arcs

function generateCloudSVG() {
  const w = 200;
  const h = 80;

  // Generate 5-8 control points around the cloud perimeter
  const numPuffs = 5 + Math.floor(Math.random() * 4);
  const points = [];

  // Top puffs - the fluffy part
  for (let i = 0; i < numPuffs; i++) {
    const t = i / numPuffs;
    const x = 15 + t * 170;
    // Create bumpy top edge - sine wave with randomness
    const baseY = 45 - Math.sin(t * Math.PI) * 25;
    const y = baseY - Math.random() * 15;
    points.push({ x, y });
  }

  // Bottom edge - flatter with slight curve
  points.push({ x: 185, y: 55 + Math.random() * 5 });
  points.push({ x: 150, y: 62 + Math.random() * 5 });
  points.push({ x: 100, y: 65 + Math.random() * 3 });
  points.push({ x: 50, y: 62 + Math.random() * 5 });
  points.push({ x: 15, y: 55 + Math.random() * 5 });

  // Build path with quadratic arcs between points for fluffy look
  let path = `M ${points[0].x.toFixed(1)} ${points[0].y.toFixed(1)}`;

  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1];
    const curr = points[i];

    // Control point creates the arc bulge
    const midX = (prev.x + curr.x) / 2;
    const midY = (prev.y + curr.y) / 2;

    // Bulge outward (up for top, down for bottom)
    const isTop = i <= numPuffs;
    const bulge = isTop ? -(12 + Math.random() * 18) : (5 + Math.random() * 8);

    const cpX = midX + (Math.random() - 0.5) * 10;
    const cpY = midY + bulge;

    path += ` Q ${cpX.toFixed(1)} ${cpY.toFixed(1)} ${curr.x.toFixed(1)} ${curr.y.toFixed(1)}`;
  }

  // Close path back to start
  const last = points[points.length - 1];
  const first = points[0];
  const closeMidX = (last.x + first.x) / 2;
  const closeMidY = (last.y + first.y) / 2 - 10;
  path += ` Q ${closeMidX.toFixed(1)} ${closeMidY.toFixed(1)} ${first.x.toFixed(1)} ${first.y.toFixed(1)}`;
  path += " Z";

  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">
    <path fill="currentColor" d="${path}"/>
  </svg>`;
}

const ClockTick = {
  mounted() { this.start(); },
  updated() { this.stop(); this.start(); },
  destroyed() { this.stop(); },

  start() {
    this.render();
    this.timer = setInterval(() => this.render(), 1000);
    this.startClouds();
  },

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.stopClouds();
  },

  // ── Cloud Animation System (game-loop with pixel positioning) ───
  startClouds() {
    // Clean up any existing state first
    this.stopClouds();

    const widget = this.el.closest(".kakemono-widget-clock");
    const container = widget?.querySelector(".kw-clock-clouds");
    if (!container) return;

    this.cloudContainer = container;
    this.cloudEntities = [];

    this.targetCloudCount = 5;
    this.lastCloudTime = performance.now();

    // Cache container dimensions to avoid layout thrashing in the animation loop
    this._cachedContainerW = 0;
    this._cachedContainerH = 0;
    this._updateCachedDimensions();

    // Update cache on resize instead of calling getBoundingClientRect every frame
    if (typeof ResizeObserver !== "undefined") {
      this._cloudResizeObserver = new ResizeObserver(() => {
        this._updateCachedDimensions();
      });
      this._cloudResizeObserver.observe(container);
    }

    // Spawn initial clouds spread across visible area
    for (let i = 0; i < this.targetCloudCount; i++) {
      this.spawnCloud(Math.random() * this._cachedContainerW * 0.8);
    }

    this.cloudLoop();
  },

  _updateCachedDimensions() {
    if (!this.cloudContainer) return;
    const rect = this.cloudContainer.getBoundingClientRect();
    this._cachedContainerW = rect.width;
    this._cachedContainerH = rect.height;
  },

  spawnCloud(startX = null) {
    if (!this.cloudContainer || !this.cloudEntities) return;

    // Use cached dimensions to avoid layout thrashing
    const containerW = this._cachedContainerW;
    const containerH = this._cachedContainerH;

    if (containerW === 0 || containerH === 0) return;

    // Cloud dimensions - wide range from small wisps to large fluffy clouds
    const heightRatio = 0.06 + Math.random() * 0.28; // 6-34% of container height
    const cloudH = containerH * heightRatio;
    const cloudW = cloudH * (200 / 80); // maintain aspect ratio

    // Start position: off-screen left if not specified
    const x = startX ?? -cloudW - Math.random() * cloudW;

    // Altitude: 5-70% from top (smaller clouds can be higher)
    const y = containerH * (0.03 + Math.random() * 0.67);

    // Speed varies with size - smaller clouds move faster (appear further away)
    const baseTime = 18 + Math.random() * 30;
    const sizeSpeedFactor = 0.6 + (heightRatio / 0.34) * 0.8; // smaller = faster
    const crossTime = baseTime * sizeSpeedFactor;
    const speed = (containerW + cloudW * 2) / crossTime;

    // Whiteness/opacity - varies from translucent wisps to bright white puffs
    const whiteness = 0.5 + Math.random() * 0.5; // 0.5-1.0
    const opacity = 0.25 + Math.random() * 0.65; // 0.25-0.9

    // Blur varies - distant (small) clouds slightly blurrier
    const blur = 0.5 + (1 - heightRatio / 0.34) * 1.5;

    const el = document.createElement("div");
    el.className = "kw-cloud-dynamic";
    el.innerHTML = generateCloudSVG();

    const entity = {
      el,
      x,
      y,
      speed,
      width: cloudW,
      height: cloudH,
      opacity,
    };

    Object.assign(el.style, {
      position: "absolute",
      left: `${x}px`,
      top: `${y}px`,
      width: `${cloudW}px`,
      height: `${cloudH}px`,
      opacity: opacity,
      color: `rgba(255, 255, 255, ${whiteness.toFixed(2)})`,
      filter: `blur(${blur.toFixed(1)}px) drop-shadow(0 2px 6px rgba(15, 23, 42, 0.1))`,
      pointerEvents: "none",
    });

    this.cloudContainer.appendChild(el);
    this.cloudEntities.push(entity);
  },

  cloudLoop() {
    if (!this.cloudContainer || !this.cloudEntities) return;

    const now = performance.now();
    const dt = (now - this.lastCloudTime) / 1000;
    this.lastCloudTime = now;

    // Use cached width to avoid layout thrashing (getBoundingClientRect is expensive)
    const containerW = this._cachedContainerW;

    // Update all clouds
    for (let i = this.cloudEntities.length - 1; i >= 0; i--) {
      const c = this.cloudEntities[i];
      c.x += c.speed * dt;
      c.el.style.left = `${c.x}px`;

      // Remove when fully off-screen right
      if (c.x > containerW + 10) {
        c.el.remove();
        c.el = null;
        this.cloudEntities.splice(i, 1);
      }
    }

    // Top up to the target count by spawning only the deficit. Bounded on
    // purpose: spawnCloud() is a no-op when the container measures 0×0 (widget
    // hidden / mid-relayout), so the old `while (length < target)` spun forever
    // and froze the tab. A fixed-count loop can't hang; unsized frames simply
    // spawn nothing and retry once the widget has size again.
    const deficit = this.targetCloudCount - this.cloudEntities.length;
    for (let i = 0; i < deficit; i++) this.spawnCloud();

    this.cloudAnimFrame = requestAnimationFrame(() => this.cloudLoop());
  },

  stopClouds() {
    if (this.cloudAnimFrame) {
      cancelAnimationFrame(this.cloudAnimFrame);
      this.cloudAnimFrame = null;
    }
    // Disconnect resize observer
    if (this._cloudResizeObserver) {
      this._cloudResizeObserver.disconnect();
      this._cloudResizeObserver = null;
    }
    // Remove all cloud DOM elements and break references
    if (this.cloudEntities) {
      for (const c of this.cloudEntities) {
        if (c.el) {
          c.el.remove();
          c.el = null;
        }
      }
      this.cloudEntities.length = 0;
    }
    this.cloudEntities = null;
    this.cloudContainer = null;
    this._cachedContainerW = 0;
    this._cachedContainerH = 0;
  },

  render() {
    const fmt = this.el.dataset.format || "24h";
    const showSeconds = (this.el.dataset.showSeconds || "false") === "true";
    const tz = this.el.dataset.timezone || undefined;
    const style = this.el.dataset.style || "celestial";
    const now = new Date();
    const widget = this.el.closest(".kakemono-widget-clock");
    const parts = this.timeParts(now, tz);

    const timeOpts = {
      hour: "2-digit",
      minute: "2-digit",
      hour12: fmt === "12h",
      timeZone: tz,
    };
    if (showSeconds) timeOpts.second = "2-digit";

    let timeStr;
    try {
      timeStr = new Intl.DateTimeFormat([], timeOpts).format(now);
    } catch (_e) {
      delete timeOpts.timeZone;
      timeStr = new Intl.DateTimeFormat([], timeOpts).format(now);
    }
    this.el.textContent = timeStr;

    const parent = this.el.parentElement;
    const root = widget || document;
    const dateEl = (parent && parent.querySelector("[data-clock-date]")) ||
                   root.querySelector("[data-clock-date]");
    if (dateEl) {
      const dateOpts = style === "minimal"
        ? { day: "numeric", month: "long", year: "numeric", timeZone: tz }
        : { weekday: "short", day: "numeric", month: "short", timeZone: tz };
      try {
        dateEl.textContent = new Intl.DateTimeFormat([], dateOpts).format(now);
      } catch (_e) {
        delete dateOpts.timeZone;
        dateEl.textContent = new Intl.DateTimeFormat([], dateOpts).format(now);
      }
    }

    if (style === "minimal") {
      const weekdayEl = root.querySelector("[data-clock-weekday]");
      if (weekdayEl) {
        const wdOpts = { weekday: "long", timeZone: tz };
        try {
          weekdayEl.textContent = new Intl.DateTimeFormat([], wdOpts).format(now);
        } catch (_e) {
          delete wdOpts.timeZone;
          weekdayEl.textContent = new Intl.DateTimeFormat([], wdOpts).format(now);
        }
      }
    }

    if (widget) {
      const hourFrac = parts.hour + parts.minute / 60 + parts.second / 3600;

      // Real daylight window when a location is configured, else fixed 6–18.
      const lat = Number.parseFloat(this.el.dataset.latitude);
      const lon = Number.parseFloat(this.el.dataset.longitude);
      const hasLocation =
        Number.isFinite(lat) && Number.isFinite(lon) && !(lat === 0 && lon === 0);

      let sun, moon, tod;
      const st = hasLocation
        ? sunTimes(now, lat, lon, tzOffsetMinutes(now, tz))
        : {};

      if (st.polarDay) {
        sun = sunPosition(hourFrac, 0, 24);
        moon = { x: 0, y: 0, visible: 0 };
        tod = "day";
      } else if (st.polarNight) {
        sun = { x: 0, y: 0, visible: 0 };
        const t = hourFrac / 24;
        moon = { x: t, y: Math.sin(Math.PI * t), visible: 1 };
        tod = "night";
      } else {
        const sunrise = st.sunrise ?? 6;
        const sunset = st.sunset ?? 18;
        sun = sunPosition(hourFrac, sunrise, sunset);
        moon = moonPosition(hourFrac, sunset, sunrise);
        tod = timeOfDay(hourFrac, sunrise, sunset);
      }

      const phase = moonPhase(now);
      const litSide = phase < 0.5 ? 1 : 0;
      const phaseDistance = Math.abs(phase - 0.5) * 2;
      const inCrescent = phaseDistance > 0.5 ? 1 : 0;
      const terminatorScale = Math.abs(phaseDistance - 0.5) * 2;
      const seconds = parts.second + now.getMilliseconds() / 1000;

      const css = widget.style;
      css.setProperty("--sun-x", sun.x.toFixed(4));
      css.setProperty("--sun-y", sun.y.toFixed(4));
      css.setProperty("--sun-visible", String(sun.visible));
      css.setProperty("--moon-x", moon.x.toFixed(4));
      css.setProperty("--moon-y", moon.y.toFixed(4));
      css.setProperty("--moon-visible", String(moon.visible));
      css.setProperty("--phase", phase.toFixed(4));
      css.setProperty("--lit-side", String(litSide));
      css.setProperty("--phase-distance", phaseDistance.toFixed(4));
      css.setProperty("--in-crescent", String(inCrescent));
      css.setProperty("--terminator-scale", terminatorScale.toFixed(4));
      css.setProperty("--hour-frac", (hourFrac / 24).toFixed(4));
      css.setProperty("--progress", (seconds / 60).toFixed(4));

      if (this.lastTod !== tod) {
        widget.setAttribute("data-tod", tod);
        this.lastTod = tod;
      }
    }
  },

  timeParts(now, tz) {
    const opts = {
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      hour12: false,
    };
    if (tz) opts.timeZone = tz;

    try {
      const byType = {};
      new Intl.DateTimeFormat("en-GB", opts).formatToParts(now).forEach((part) => {
        byType[part.type] = part.value;
      });

      const hour = Number.parseInt(byType.hour || "0", 10);
      const minute = Number.parseInt(byType.minute || "0", 10);
      const second = Number.parseInt(byType.second || "0", 10);

      return {
        hour: Number.isFinite(hour) ? hour % 24 : now.getHours(),
        minute: Number.isFinite(minute) ? minute : now.getMinutes(),
        second: Number.isFinite(second) ? second : now.getSeconds(),
      };
    } catch (_e) {
      return {
        hour: now.getHours(),
        minute: now.getMinutes(),
        second: now.getSeconds(),
      };
    }
  }
};

export default ClockTick;
