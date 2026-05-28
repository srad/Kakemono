import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import ClockTick from "../js/hooks/clock_tick.js"

// Regression tests for the cloud-maintenance loop in ClockTick.cloudLoop().
//
// The bug: cloudLoop() topped up clouds with `while (length < target)
// spawnCloud()`, but spawnCloud() is a no-op when the container measures
// 0×0 (widget hidden / mid-relayout). That made the while-loop spin
// forever on a zero-sized container — a synchronous infinite loop that
// hard-freezes the browser tab. The fix bounds the loop.

function makeCtx({ width, height }) {
  // A real (jsdom) element so spawnCloud's appendChild works.
  const container = document.createElement("div")
  return {
    cloudContainer: container,
    cloudEntities: [],
    targetCloudCount: 5,
    lastCloudTime: 0,
    _cachedContainerW: width,
    _cachedContainerH: height,
    // bind the methods under test to this fake context
    spawnCloud: ClockTick.spawnCloud,
    cloudLoop: ClockTick.cloudLoop,
  }
}

describe("ClockTick.cloudLoop cloud maintenance", () => {
  beforeEach(() => {
    // Prevent the rAF tail-call from actually re-entering cloudLoop.
    vi.stubGlobal("requestAnimationFrame", vi.fn(() => 1))
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("terminates (does not hang) when the container is 0×0", () => {
    const ctx = makeCtx({ width: 0, height: 0 })

    // If the loop were unbounded this call would never return and the test
    // would time out. Reaching the assertions proves it terminates.
    ctx.cloudLoop()

    expect(ctx.cloudEntities.length).toBe(0)
    expect(globalThis.requestAnimationFrame).toHaveBeenCalledTimes(1)
  })

  it("attempts at most the deficit, and stays empty, on a zero-sized container", () => {
    const ctx = makeCtx({ width: 0, height: 0 })
    const spy = vi.spyOn(ctx, "spawnCloud")

    ctx.cloudLoop()

    // The loop is bounded by the deficit (target 5 - current 0 = 5), so it can
    // never spin. Every spawn is a no-op on a 0×0 container, so no clouds are
    // added.
    expect(spy.mock.calls.length).toBeLessThanOrEqual(ctx.targetCloudCount)
    expect(ctx.cloudEntities.length).toBe(0)
  })

  it("fills up to targetCloudCount when the container has size", () => {
    const ctx = makeCtx({ width: 300, height: 150 })

    ctx.cloudLoop()

    expect(ctx.cloudEntities.length).toBe(ctx.targetCloudCount)
  })

  it("only tops up the deficit on subsequent frames", () => {
    const ctx = makeCtx({ width: 300, height: 150 })
    ctx.cloudLoop()
    expect(ctx.cloudEntities.length).toBe(5)

    // Simulate one cloud drifting off-screen and being removed.
    ctx.cloudEntities.pop()
    const spy = vi.spyOn(ctx, "spawnCloud")

    ctx.cloudLoop()

    expect(spy).toHaveBeenCalledTimes(1)
    expect(ctx.cloudEntities.length).toBe(5)
  })
})

describe("ClockTick.spawnCloud guard", () => {
  it("is a no-op when the container measures 0×0", () => {
    const container = document.createElement("div")
    const ctx = {
      cloudContainer: container,
      cloudEntities: [],
      _cachedContainerW: 0,
      _cachedContainerH: 0,
    }

    ClockTick.spawnCloud.call(ctx)

    expect(ctx.cloudEntities.length).toBe(0)
    expect(container.children.length).toBe(0)
  })

  it("appends a cloud element when the container has size", () => {
    const container = document.createElement("div")
    const ctx = {
      cloudContainer: container,
      cloudEntities: [],
      _cachedContainerW: 300,
      _cachedContainerH: 150,
    }

    ClockTick.spawnCloud.call(ctx)

    expect(ctx.cloudEntities.length).toBe(1)
    expect(container.children.length).toBe(1)
  })
})
