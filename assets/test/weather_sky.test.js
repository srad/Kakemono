import { describe, it, expect, vi, afterEach } from "vitest"
import WeatherSky from "../../lib/kakemono/widgets/weather/weather_sky.js"

function weatherEl(attrs = {}) {
  const el = document.createElement("div")
  el.setAttribute("data-tod", attrs.tod ?? "night")
  el.setAttribute("data-is-day", attrs.isDay ?? "0")
  if (attrs.latitude !== undefined) el.dataset.latitude = attrs.latitude
  if (attrs.longitude !== undefined) el.dataset.longitude = attrs.longitude
  if (attrs.utcOffset !== undefined) el.dataset.utcOffset = attrs.utcOffset
  if (attrs.timezone !== undefined) el.dataset.timezone = attrs.timezone
  return el
}

function renderAt(iso, el, ctx = {}) {
  vi.useFakeTimers()
  vi.setSystemTime(new Date(iso))
  WeatherSky.render.call({ el, ...ctx })
}

describe("WeatherSky.render", () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it("repairs stale DOM attributes after a LiveView patch", () => {
    const el = weatherEl({ tod: "night", isDay: "0", utcOffset: "0" })

    renderAt("2026-05-29T12:00:00Z", el, { lastTod: "day" })

    expect(el.dataset.tod).toBe("day")
    expect(el.dataset.isDay).toBe("1")
  })

  it("uses data-timezone when no provider UTC offset is present", () => {
    const el = weatherEl({ timezone: "America/New_York" })

    renderAt("2026-05-29T21:30:00Z", el)

    expect(el.dataset.tod).toBe("dusk")
    expect(el.dataset.isDay).toBe("1")
  })

  it("publishes daytime sun variables for the location", () => {
    const el = weatherEl({
      latitude: "52.52",
      longitude: "13.405",
      timezone: "Europe/Berlin",
    })

    renderAt("2026-06-21T12:00:00Z", el)

    expect(el.dataset.tod).toBe("day")
    expect(el.style.getPropertyValue("--sun-visible")).toBe("1")
    expect(el.style.getPropertyValue("--moon-visible")).toBe("0")
    expect(Number(el.style.getPropertyValue("--sun-x"))).toBeGreaterThan(0)
    expect(Number(el.style.getPropertyValue("--sun-y"))).toBeGreaterThan(0)
  })

  it("publishes night moon and darkness variables after local sunset", () => {
    const el = weatherEl({
      latitude: "52.52",
      longitude: "13.405",
      timezone: "Europe/Berlin",
    })

    renderAt("2026-06-21T22:30:00Z", el)

    expect(el.dataset.tod).toBe("night")
    expect(el.dataset.isDay).toBe("0")
    expect(el.style.getPropertyValue("--sun-visible")).toBe("0")
    expect(el.style.getPropertyValue("--moon-visible")).toBe("1")
    expect(Number(el.style.getPropertyValue("--night-strength"))).toBeGreaterThan(0.9)
    expect(Number(el.style.getPropertyValue("--star-strength"))).toBeGreaterThan(0.1)
    expect(Number(el.style.getPropertyValue("--star-strength"))).toBeLessThan(1)
  })

  it("keeps stars hidden during late-sunset twilight", () => {
    const el = weatherEl({
      latitude: "52.52",
      longitude: "13.405",
      timezone: "Europe/Berlin",
    })

    renderAt("2026-06-21T20:00:00Z", el)

    expect(el.dataset.tod).toBe("dusk")
    expect(el.style.getPropertyValue("--sun-visible")).toBe("0")
    expect(Number(el.style.getPropertyValue("--star-strength"))).toBe(0)
  })

  it("keeps polar day visually stable", () => {
    const el = weatherEl({
      latitude: "78",
      longitude: "15",
      utcOffset: "3600",
    })

    renderAt("2026-06-21T12:00:00Z", el)

    expect(el.dataset.tod).toBe("day")
    expect(el.style.getPropertyValue("--sun-visible")).toBe("1")
    expect(el.style.getPropertyValue("--moon-visible")).toBe("0")
    expect(el.style.getPropertyValue("--night-strength")).toBe("0.0000")
    expect(el.style.getPropertyValue("--star-strength")).toBe("0.0000")
  })

  it("keeps polar night visually stable", () => {
    const el = weatherEl({
      latitude: "78",
      longitude: "15",
      utcOffset: "3600",
    })

    renderAt("2026-12-21T12:00:00Z", el)

    expect(el.dataset.tod).toBe("night")
    expect(el.style.getPropertyValue("--sun-visible")).toBe("0")
    expect(el.style.getPropertyValue("--moon-visible")).toBe("1")
    expect(el.style.getPropertyValue("--night-strength")).toBe("1.0000")
    expect(Number(el.style.getPropertyValue("--star-strength"))).toBeGreaterThan(0)
  })
})
