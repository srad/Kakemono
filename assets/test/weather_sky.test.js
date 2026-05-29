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
})
