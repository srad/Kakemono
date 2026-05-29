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

// Generate a smooth puffy cloud with built-in transparent padding so the
// rasterized edge/shadow does not get clipped on low-end Android WebViews.

function generateCloudShape() {
  const w = 240;
  const h = 104;
  const pad = 20;
  const puffs = [
    { cx: rand(50, 58), cy: rand(62, 68), rx: rand(25, 32), ry: rand(18, 24) },
    { cx: rand(72, 84), cy: rand(50, 58), rx: rand(34, 44), ry: rand(25, 34) },
    { cx: rand(106, 120), cy: rand(39, 49), rx: rand(38, 50), ry: rand(30, 40) },
    { cx: rand(142, 156), cy: rand(45, 55), rx: rand(34, 45), ry: rand(25, 34) },
    { cx: rand(180, 190), cy: rand(58, 66), rx: rand(27, 34), ry: rand(20, 27) },
    { cx: rand(87, 104), cy: rand(68, 75), rx: rand(42, 54), ry: rand(17, 23) },
    { cx: rand(128, 148), cy: rand(70, 77), rx: rand(45, 58), ry: rand(17, 24) },
    { cx: rand(156, 174), cy: rand(69, 76), rx: rand(34, 46), ry: rand(16, 22) },
  ];
  return { w, h, pad, puffs };
}

function rand(min, max) {
  return min + Math.random() * (max - min);
}

function cloudSVG(shape) {
  return `<svg viewBox="0 0 ${shape.w} ${shape.h}" preserveAspectRatio="xMidYMid meet">
    <g fill="currentColor">
      ${shape.puffs
        .map((p, i) => `<ellipse cx="${p.cx.toFixed(1)}" cy="${p.cy.toFixed(1)}" rx="${p.rx.toFixed(1)}" ry="${p.ry.toFixed(1)}" opacity="${i < 5 ? "0.96" : "0.82"}"/>`)
        .join("")}
    </g>
  </svg>`;
}

function drawCloudBody(ctx, shape) {
  ctx.beginPath();
  for (const puff of shape.puffs) {
    ctx.moveTo(puff.cx + puff.rx, puff.cy);
    ctx.ellipse(puff.cx, puff.cy, puff.rx, puff.ry, 0, 0, Math.PI * 2);
  }
}

function fallbackCloudVisual(shape) {
  const visual = document.createElement("div");
  visual.className = "kw-cloud-visual";
  visual.innerHTML = cloudSVG(shape);
  return visual;
}

function rasterCloudVisual(shape, cloudW, cloudH, whiteness, blur) {
  const canvas = document.createElement("canvas");
  const dpr = Math.min(Math.max(window.devicePixelRatio || 1, 1), 1.5);
  const pixelW = Math.max(1, Math.ceil(cloudW * dpr));
  const pixelH = Math.max(1, Math.ceil(cloudH * dpr));
  canvas.className = "kw-cloud-canvas";
  canvas.width = pixelW;
  canvas.height = pixelH;

  let ctx;
  try {
    ctx = canvas.getContext("2d");
  } catch (_e) {
    return null;
  }
  if (!ctx) return null;
  if (typeof ctx.ellipse !== "function") return null;
  if (
    typeof ctx.createRadialGradient !== "function" ||
    typeof ctx.createLinearGradient !== "function"
  ) {
    return null;
  }

  const scaleX = pixelW / shape.w;
  const scaleY = pixelH / shape.h;
  ctx.setTransform(scaleX, 0, 0, scaleY, 0, 0);

  ctx.clearRect(0, 0, shape.w, shape.h);

  // One soft whole-cloud pass gives the puffs cohesion without requiring a
  // moving CSS filter.
  ctx.shadowColor = "rgba(15, 23, 42, 0.14)";
  ctx.shadowBlur = Math.max(1.5, blur * 3);
  ctx.shadowOffsetY = 2;
  ctx.fillStyle = `rgba(255, 255, 255, ${Math.min(1, whiteness * 0.78).toFixed(3)})`;
  drawCloudBody(ctx, shape);
  ctx.fill();

  ctx.shadowColor = "transparent";
  ctx.shadowBlur = 0;
  ctx.shadowOffsetY = 0;

  for (const puff of shape.puffs) {
    const grad = ctx.createRadialGradient(
      puff.cx - puff.rx * 0.35,
      puff.cy - puff.ry * 0.45,
      Math.max(1, puff.rx * 0.08),
      puff.cx,
      puff.cy,
      puff.rx * 1.16,
    );
    grad.addColorStop(0, `rgba(255, 255, 255, ${whiteness.toFixed(3)})`);
    grad.addColorStop(0.58, `rgba(255, 255, 255, ${(whiteness * 0.94).toFixed(3)})`);
    grad.addColorStop(1, `rgba(214, 226, 240, ${(whiteness * 0.74).toFixed(3)})`);
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.ellipse(puff.cx, puff.cy, puff.rx, puff.ry, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  const underside = ctx.createLinearGradient(0, shape.h * 0.38, 0, shape.h * 0.86);
  underside.addColorStop(0, "rgba(255, 255, 255, 0)");
  underside.addColorStop(0.68, `rgba(174, 197, 223, ${(whiteness * 0.13).toFixed(3)})`);
  underside.addColorStop(1, `rgba(104, 132, 166, ${(whiteness * 0.22).toFixed(3)})`);
  ctx.fillStyle = underside;
  drawCloudBody(ctx, shape);
  ctx.fill();

  const highlight = ctx.createLinearGradient(0, shape.h * 0.12, 0, shape.h * 0.62);
  highlight.addColorStop(0, `rgba(255, 255, 255, ${(whiteness * 0.25).toFixed(3)})`);
  highlight.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = highlight;
  for (const puff of shape.puffs.slice(1, 5)) {
    ctx.beginPath();
    ctx.ellipse(puff.cx - puff.rx * 0.08, puff.cy - puff.ry * 0.2, puff.rx * 0.62, puff.ry * 0.42, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  return canvas;
}

function createCloudVisual(shape, cloudW, cloudH, whiteness, blur) {
  return rasterCloudVisual(shape, cloudW, cloudH, whiteness, blur) || fallbackCloudVisual(shape);
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

  // ── Cloud Animation System (CSS transform animation) ────────────
  startClouds() {
    // Clean up any existing state first
    this.stopClouds();

    const widget = this.el.closest(".kakemono-widget-clock");
    const container = widget?.querySelector(".kw-clock-clouds");
    if (!container) return;

    this.cloudContainer = container;
    this.cloudEntities = [];

    this.targetCloudCount = 5;

    // Cache container dimensions; CSS owns per-frame movement.
    this._cachedContainerW = 0;
    this._cachedContainerH = 0;
    this._updateCachedDimensions();

    // Update cache on resize instead of calling getBoundingClientRect every frame
    if (typeof ResizeObserver !== "undefined") {
      this._cloudResizeObserver = new ResizeObserver(() => {
        this._updateCachedDimensions();
        this.topUpClouds({ spread: this.cloudEntities?.length === 0 });
      });
      this._cloudResizeObserver.observe(container);
    }

    // Spawn initial clouds spread across visible area
    this.topUpClouds({ spread: true });
  },

  _updateCachedDimensions() {
    if (!this.cloudContainer) return;
    const rect = this.cloudContainer.getBoundingClientRect();
    this._cachedContainerW = rect.width;
    this._cachedContainerH = rect.height;
  },

  topUpClouds({ spread = false } = {}) {
    if (!this.cloudContainer || !this.cloudEntities) return;

    const deficit = this.targetCloudCount - this.cloudEntities.length;
    for (let i = 0; i < deficit; i++) {
      const startX = spread ? Math.random() * this._cachedContainerW * 0.8 : null;
      this.spawnCloud(startX);
    }
  },

  spawnCloud(startX = null) {
    if (!this.cloudContainer || !this.cloudEntities) return;

    // Use cached dimensions to avoid layout thrashing
    const containerW = this._cachedContainerW;
    const containerH = this._cachedContainerH;

    if (containerW === 0 || containerH === 0) return;

    // Cloud dimensions - wide range from small wisps to large fluffy clouds
    const heightRatio = 0.06 + Math.random() * 0.28; // 6-34% of container height
    const shape = generateCloudShape();
    const cloudH = containerH * heightRatio;
    const cloudW = cloudH * (shape.w / shape.h); // maintain padded raster aspect ratio

    // Start position: off-screen left if not specified
    const x = startX ?? -cloudW - Math.random() * cloudW;

    // Altitude: 5-70% from top (smaller clouds can be higher)
    const y = containerH * (0.03 + Math.random() * 0.67);

    // Speed varies with size - smaller clouds move faster (appear further away)
    const baseTime = 18 + Math.random() * 30;
    const sizeSpeedFactor = 0.6 + (heightRatio / 0.34) * 0.8; // smaller = faster
    const crossTime = baseTime * sizeSpeedFactor;
    const speed = (containerW + cloudW * 2) / crossTime;
    const endX = containerW + 10;
    const duration = Math.max(6, (endX - x) / speed);

    // Whiteness/opacity - varies from translucent wisps to bright white puffs
    const whiteness = 0.5 + Math.random() * 0.5; // 0.5-1.0
    const opacity = 0.25 + Math.random() * 0.65; // 0.25-0.9

    // Blur varies - distant (small) clouds slightly blurrier
    const blur = 0.5 + (1 - heightRatio / 0.34) * 1.5;

    const el = document.createElement("div");
    el.className = "kw-cloud-dynamic";
    el.appendChild(createCloudVisual(shape, cloudW, cloudH, whiteness, blur));

    const entity = {
      el,
      width: cloudW,
      height: cloudH,
      opacity,
      puffCount: shape.puffs.length,
      padding: shape.pad,
    };
    entity.onDone = (event) => {
      if (event.target === el) this.finishCloud(entity);
    };
    entity.recycleTimer = setTimeout(() => this.finishCloud(entity), (duration + 0.5) * 1000);
    if (typeof entity.recycleTimer.unref === "function") entity.recycleTimer.unref();

    Object.assign(el.style, {
      top: `${y}px`,
      width: `${cloudW}px`,
      height: `${cloudH}px`,
      opacity: opacity,
      color: `rgba(255, 255, 255, ${whiteness.toFixed(2)})`,
      pointerEvents: "none",
    });
    el.style.setProperty("--cloud-from", `${x}px`);
    el.style.setProperty("--cloud-to", `${endX}px`);
    el.style.setProperty("--cloud-duration", `${duration.toFixed(2)}s`);
    el.addEventListener("animationend", entity.onDone);

    this.cloudContainer.appendChild(el);
    this.cloudEntities.push(entity);
  },

  finishCloud(entity) {
    if (!this.cloudContainer || !this.cloudEntities) return;

    const index = this.cloudEntities.indexOf(entity);
    if (index !== -1) this.cloudEntities.splice(index, 1);
    if (entity.recycleTimer) {
      clearTimeout(entity.recycleTimer);
      entity.recycleTimer = null;
    }
    if (entity.el) {
      entity.el.removeEventListener("animationend", entity.onDone);
      entity.el.remove();
      entity.el = null;
    }

    this.topUpClouds();
  },

  stopClouds() {
    // Disconnect resize observer
    if (this._cloudResizeObserver) {
      this._cloudResizeObserver.disconnect();
      this._cloudResizeObserver = null;
    }
    // Remove all cloud DOM elements and break references
    if (this.cloudEntities) {
      for (const c of this.cloudEntities) {
        if (c.recycleTimer) {
          clearTimeout(c.recycleTimer);
          c.recycleTimer = null;
        }
        if (c.el) {
          c.el.removeEventListener("animationend", c.onDone);
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

      if (widget.getAttribute("data-tod") !== tod) {
        widget.setAttribute("data-tod", tod);
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
