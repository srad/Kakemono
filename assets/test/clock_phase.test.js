import { describe, it, expect } from "vitest"
import { moonPhase, sunPosition, moonPosition, timeOfDay } from "../../lib/kakemono/widgets/clock/clock_tick.js"

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
  it("maps hours to dawn/day/dusk/night buckets", () => {
    expect(timeOfDay(6)).toBe("dawn")
    expect(timeOfDay(12)).toBe("day")
    expect(timeOfDay(18)).toBe("dusk")
    expect(timeOfDay(22)).toBe("night")
    expect(timeOfDay(2)).toBe("night")
  })
})
