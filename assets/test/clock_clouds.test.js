import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import ClockTick from "../../lib/kakemono/widgets/clock/clock_tick.js"

// Regression tests for clock clouds. The animation is CSS transform based so
// Android WebView can move clouds on the compositor without per-frame layout.
// JS only spawns/recycles cloud elements and must stay bounded when a widget is
// hidden or mid-relayout with a 0×0 container.

function makeCtx({ width, height, target = 5 }) {
  // A real (jsdom) element so spawnCloud's appendChild works.
  const container = document.createElement("div")
  return {
    cloudContainer: container,
    cloudEntities: [],
    targetCloudCount: target,
    _cachedContainerW: width,
    _cachedContainerH: height,
    // bind the methods under test to this fake context
    spawnCloud: ClockTick.spawnCloud,
    topUpClouds: ClockTick.topUpClouds,
    finishCloud: ClockTick.finishCloud,
  }
}

describe("ClockTick CSS cloud animation maintenance", () => {
  beforeEach(() => {
    vi.stubGlobal("requestAnimationFrame", vi.fn())
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("terminates (does not hang) when the container is 0×0", () => {
    const ctx = makeCtx({ width: 0, height: 0 })

    // If top-up were unbounded this call would never return and the test
    // would time out. Reaching the assertions proves it terminates.
    ctx.topUpClouds()

    expect(ctx.cloudEntities.length).toBe(0)
    expect(globalThis.requestAnimationFrame).not.toHaveBeenCalled()
  })

  it("attempts at most the deficit, and stays empty, on a zero-sized container", () => {
    const ctx = makeCtx({ width: 0, height: 0 })
    const spy = vi.spyOn(ctx, "spawnCloud")

    ctx.topUpClouds()

    // Top-up is bounded by the deficit (target 5 - current 0 = 5), so it can
    // never spin. Every spawn is a no-op on a 0×0 container.
    expect(spy.mock.calls.length).toBeLessThanOrEqual(ctx.targetCloudCount)
    expect(ctx.cloudEntities.length).toBe(0)
  })

  it("fills up to targetCloudCount when the container has size", () => {
    const ctx = makeCtx({ width: 300, height: 150 })

    ctx.topUpClouds()

    expect(ctx.cloudEntities.length).toBe(ctx.targetCloudCount)
    expect(ctx.cloudContainer.children.length).toBe(ctx.targetCloudCount)
  })

  it("only tops up the deficit on subsequent top-ups", () => {
    const ctx = makeCtx({ width: 300, height: 150 })
    ctx.topUpClouds()
    expect(ctx.cloudEntities.length).toBe(5)

    const removed = ctx.cloudEntities.pop()
    removed.el.remove()
    const spy = vi.spyOn(ctx, "spawnCloud")

    ctx.topUpClouds()

    expect(spy).toHaveBeenCalledTimes(1)
    expect(ctx.cloudEntities.length).toBe(5)
  })

  it("recycles a cloud on CSS animationend", () => {
    const ctx = makeCtx({ width: 300, height: 150, target: 1 })
    ctx.spawnCloud(0)
    const first = ctx.cloudEntities[0].el

    first.dispatchEvent(new Event("animationend"))

    expect(first.isConnected).toBe(false)
    expect(ctx.cloudEntities.length).toBe(1)
    expect(ctx.cloudEntities[0].el).not.toBe(first)
    expect(ctx.cloudContainer.children.length).toBe(1)
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
      targetCloudCount: 5,
      _cachedContainerW: 300,
      _cachedContainerH: 150,
      topUpClouds: ClockTick.topUpClouds,
      finishCloud: ClockTick.finishCloud,
    }

    ClockTick.spawnCloud.call(ctx, 12)

    expect(ctx.cloudEntities.length).toBe(1)
    expect(container.children.length).toBe(1)
    expect(container.children[0].style.left).toBe("")
    expect(container.children[0].style.getPropertyValue("--cloud-from")).toBe("12px")
    expect(container.children[0].style.getPropertyValue("--cloud-to")).toBe("310px")
    expect(container.children[0].style.getPropertyValue("--cloud-duration")).toMatch(/s$/)
    expect(container.querySelector(".kw-cloud-visual")).not.toBeNull()
  })
})
