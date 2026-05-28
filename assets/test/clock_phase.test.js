import { describe, it, expect } from "vitest"
import {
  moonPhase,
  sunPosition,
  moonPosition,
  timeOfDay,
  sunTimes,
  tzOffsetMinutes,
} from "../../lib/kakemono/widgets/clock/clock_tick.js"

const BERLIN = { lat: 52.52, lon: 13.405 }

describe("moonPhase", () => {
  it("returns ~0 at the new moon epoch", () => {
    const newMoon = new Date(Date.UTC(2000, 0, 6, 18, 14, 0))
    expect(moonPhase(newMoon)).toBeCloseTo(0, 3)
  })

  it("returns ~0.5 at full moon (half a synodic cycle later)", () => {
    const synodic = 29.530588853
    const newMoonMs = Date.UTC(2000, 0, 6, 18, 14, 0)
    const fullMoon = new Date(newMoonMs + (synodic / 2) * 86400_000)
    expect(moonPhase(fullMoon)).toBeCloseTo(0.5, 3)
  })

  it("stays within [0, 1) for all inputs", () => {
    const samples = [
      new Date("1995-04-12T00:00:00Z"),
      new Date("2010-08-21T12:00:00Z"),
      new Date("2026-05-27T03:45:00Z"),
      new Date("2099-12-31T23:59:59Z"),
    ]
    for (const d of samples) {
      const p = moonPhase(d)
      expect(p).toBeGreaterThanOrEqual(0)
      expect(p).toBeLessThan(1)
    }
  })
})

describe("sunPosition", () => {
  it("is invisible before sunrise and after sunset", () => {
    expect(sunPosition(3).visible).toBe(0)
    expect(sunPosition(5.99).visible).toBe(0)
    expect(sunPosition(18.01).visible).toBe(0)
    expect(sunPosition(22).visible).toBe(0)
  })

  it("peaks at noon", () => {
    const noon = sunPosition(12)
    expect(noon.visible).toBe(1)
    expect(noon.x).toBeCloseTo(0.5, 3)
    expect(noon.y).toBeCloseTo(1, 3)
  })

  it("rises on the left and sets on the right", () => {
    const morning = sunPosition(6)
    const evening = sunPosition(18)
    expect(morning.x).toBeCloseTo(0, 3)
    expect(morning.y).toBeCloseTo(0, 3)
    expect(evening.x).toBeCloseTo(1, 3)
    expect(evening.y).toBeCloseTo(0, 3)
  })
})

describe("moonPosition", () => {
  it("is invisible during daylight hours", () => {
    expect(moonPosition(8).visible).toBe(0)
    expect(moonPosition(12).visible).toBe(0)
    expect(moonPosition(17.99).visible).toBe(0)
  })

  it("rises at 18:00 and sets at 06:00 next morning", () => {
    expect(moonPosition(18).x).toBeCloseTo(0, 3)
    expect(moonPosition(18).y).toBeCloseTo(0, 3)
    expect(moonPosition(0).x).toBeCloseTo(0.5, 3)
    expect(moonPosition(0).y).toBeCloseTo(1, 3)
    const set = moonPosition(5.999)
    expect(set.visible).toBe(1)
    expect(set.x).toBeCloseTo(1, 2)
  })
})

describe("timeOfDay", () => {
  it("maps hours to dawn/day/dusk/night buckets (fixed-window fallback)", () => {
    expect(timeOfDay(6)).toBe("dawn")
    expect(timeOfDay(12)).toBe("day")
    expect(timeOfDay(18)).toBe("dusk")
    expect(timeOfDay(22)).toBe("night")
    expect(timeOfDay(2)).toBe("night")
  })

  it("tracks a real daylight window when given one", () => {
    // Long summer day: sunrise ~5, sunset ~21.
    expect(timeOfDay(13, 5, 21)).toBe("day")
    expect(timeOfDay(20, 5, 21)).toBe("dusk")
    expect(timeOfDay(22, 5, 21)).toBe("night")
    expect(timeOfDay(5, 5, 21)).toBe("dawn")
  })
})

describe("sunTimes", () => {
  it("yields a long day near the summer solstice in Berlin", () => {
    const date = new Date(Date.UTC(2026, 5, 21, 12, 0, 0))
    const { sunrise, sunset, polarDay, polarNight } = sunTimes(
      date, BERLIN.lat, BERLIN.lon, 120, // CEST = UTC+2
    )
    expect(polarDay).toBeUndefined()
    expect(polarNight).toBeUndefined()
    expect(sunrise).toBeLessThan(5.0)   // sun is up well before 05:00
    expect(sunset).toBeGreaterThan(21.0) // and still up after 21:00
  })

  it("yields a ~12h day near the equinox in Berlin", () => {
    const date = new Date(Date.UTC(2026, 2, 20, 12, 0, 0))
    const { sunrise, sunset } = sunTimes(date, BERLIN.lat, BERLIN.lon, 60) // CET
    expect(sunrise).toBeCloseTo(6, 0)
    expect(sunset).toBeCloseTo(18, 0)
    expect(sunset - sunrise).toBeGreaterThan(11.5)
    expect(sunset - sunrise).toBeLessThan(12.7)
  })

  it("flags polar day / polar night at high latitudes", () => {
    const midsummer = new Date(Date.UTC(2026, 5, 21, 12, 0, 0))
    const midwinter = new Date(Date.UTC(2026, 11, 21, 12, 0, 0))
    expect(sunTimes(midsummer, 78, 15, 60).polarDay).toBe(true)
    expect(sunTimes(midwinter, 78, 15, 60).polarNight).toBe(true)
  })
})

describe("sunPosition with a real window", () => {
  it("keeps the sun up in the evening on a long summer day", () => {
    // Window 5 → 21: at 20:00 the sun is still above the horizon.
    expect(sunPosition(20, 5, 21).visible).toBe(1)
    // The old fixed 6–18 window had already set it by 18:01.
    expect(sunPosition(18.01).visible).toBe(0)
  })
})

describe("moonPosition with a real window", () => {
  it("does not raise the moon before the real sunset", () => {
    // Sunset 21:00: at 19:00 the moon has not yet risen.
    expect(moonPosition(19, 21, 5).visible).toBe(0)
    // It rises once past sunset.
    expect(moonPosition(22, 21, 5).visible).toBe(1)
  })
})

describe("tzOffsetMinutes", () => {
  it("returns 0 for UTC", () => {
    expect(tzOffsetMinutes(new Date(Date.UTC(2026, 5, 1, 12)), "UTC")).toBe(0)
  })

  it("returns +120 for Berlin in summer (CEST)", () => {
    expect(
      tzOffsetMinutes(new Date(Date.UTC(2026, 5, 21, 12)), "Europe/Berlin"),
    ).toBe(120)
  })
})
