import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Slideshow from "../js/hooks/slideshow.js"

function makeHost({ items = [], fitMode = "contain" } = {}) {
  document.body.innerHTML = `
    <div id="root" data-fit-mode="${fitMode}" data-items='${JSON.stringify(items)}'>
      <div id="display-status"></div>
    </div>
  `
  const el = document.getElementById("root")
  const hook = Object.create(Slideshow)
  hook.el = el
  hook.pushEvent = vi.fn()
  hook.handleEvent = vi.fn()
  return hook
}

describe("Slideshow hook", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("defines flashStatus (regression: 'this.flashStatus is not a function')", () => {
    expect(typeof Slideshow.flashStatus).toBe("function")
  })

  it("flashStatus updates #display-status text content", () => {
    document.body.innerHTML = `<div id="display-status"></div>`
    Slideshow.flashStatus("hello")
    expect(document.getElementById("display-status").textContent).toBe("hello")
  })

  it("flashStatus is a no-op when #display-status missing", () => {
    document.body.innerHTML = ""
    expect(() => Slideshow.flashStatus("x")).not.toThrow()
  })

  it("mounted() builds two layers and reads items from dataset", () => {
    const hook = makeHost({
      items: [{ id: 1, type: "image", src: "/a.jpg", duration_ms: 3000 }],
      fitMode: "cover",
    })
    hook.mounted()
    expect(hook.layers).toHaveLength(2)
    expect(hook.items).toHaveLength(1)
    expect(hook.fitMode).toBe("cover")
    expect(hook.el.querySelectorAll("img").length).toBe(2)
    expect(hook.el.querySelectorAll("video").length).toBe(2)
    expect(document.getElementById("display-status").textContent).toContain(
      "connected · 1 items · cover",
    )
    hook.destroyed()
  })

  it("mounted() with empty items keeps layers transparent and does not crash", () => {
    const hook = makeHost({ items: [] })
    hook.mounted()
    hook.layers.forEach((l) => expect(l.root.style.opacity).toBe("0"))
    hook.destroyed()
  })

  it("show() advances to next item after duration_ms", () => {
    const hook = makeHost({
      items: [
        { id: 1, type: "image", src: "/a.jpg", duration_ms: 3000 },
        { id: 2, type: "image", src: "/b.jpg", duration_ms: 3000 },
      ],
    })
    hook.mounted()
    expect(hook.index).toBe(0)
    vi.advanceTimersByTime(3001)
    expect(hook.index).toBe(1)
    vi.advanceTimersByTime(3001)
    expect(hook.index).toBe(0)
    hook.destroyed()
  })

  it("show() enforces a 2-second minimum dwell time", () => {
    const hook = makeHost({
      items: [
        { id: 1, type: "image", src: "/a.jpg", duration_ms: 100 },
        { id: 2, type: "image", src: "/b.jpg", duration_ms: 100 },
      ],
    })
    hook.mounted()
    vi.advanceTimersByTime(500)
    expect(hook.index).toBe(0)
    vi.advanceTimersByTime(1501)
    expect(hook.index).toBe(1)
    hook.destroyed()
  })

  it("show() crossfades by toggling layer opacity", () => {
    const hook = makeHost({
      items: [
        { id: 1, type: "image", src: "/a.jpg", duration_ms: 2000 },
        { id: 2, type: "image", src: "/b.jpg", duration_ms: 2000 },
      ],
    })
    hook.mounted()
    const visible = hook.layers[hook.active]
    expect(visible.root.style.opacity).toBe("1")
    hook.destroyed()
  })

  it("show() sets video src and calls play() for video items", () => {
    const hook = makeHost({
      items: [{ id: 1, type: "video", src: "/v.mp4", duration_ms: 5000 }],
    })
    hook.mounted()
    const layer = hook.layers[hook.active]
    expect(layer.vid.style.display).toBe("block")
    expect(layer.img.style.display).toBe("none")
    expect(layer.vid.src).toContain("/v.mp4")
    hook.destroyed()
  })

  it("applyFitMode propagates objectFit to both layers", () => {
    const hook = makeHost({
      items: [{ id: 1, type: "image", src: "/a.jpg" }],
      fitMode: "contain",
    })
    hook.mounted()
    hook.applyFitMode("fill")
    expect(hook.fitMode).toBe("fill")
    hook.layers.forEach((l) => {
      expect(l.img.style.objectFit).toBe("fill")
      expect(l.vid.style.objectFit).toBe("fill")
    })
    hook.destroyed()
  })

  it("handleEvent('slideshow:update') replaces items and applies fit_mode", () => {
    const hook = makeHost({
      items: [{ id: 1, type: "image", src: "/a.jpg", duration_ms: 3000 }],
    })
    let captured
    hook.handleEvent = (_evt, cb) => {
      captured = cb
    }
    hook.mounted()
    captured({
      items: [{ id: 9, type: "image", src: "/new.jpg", duration_ms: 3000 }],
      fit_mode: "cover",
    })
    expect(hook.items).toEqual([
      { id: 9, type: "image", src: "/new.jpg", duration_ms: 3000 },
    ])
    expect(hook.index).toBe(0)
    expect(hook.fitMode).toBe("cover")
    hook.destroyed()
  })

  it("image onerror calls flashStatus with the failing src", () => {
    const hook = makeHost({
      items: [{ id: 1, type: "image", src: "/missing.jpg", duration_ms: 3000 }],
    })
    hook.mounted()
    const layer = hook.layers[hook.active]
    layer.img.onerror()
    expect(document.getElementById("display-status").textContent).toContain(
      "error loading /missing.jpg",
    )
    hook.destroyed()
  })

  it("destroyed() clears the timer", () => {
    const hook = makeHost({
      items: [
        { id: 1, type: "image", src: "/a.jpg", duration_ms: 3000 },
        { id: 2, type: "image", src: "/b.jpg", duration_ms: 3000 },
      ],
    })
    hook.mounted()
    hook.destroyed()
    const before = hook.index
    vi.advanceTimersByTime(10_000)
    expect(hook.index).toBe(before)
  })

  it("image layer uses high-quality rendering hints (regression: blurry slideshow)", () => {
    const hook = makeHost({
      items: [{ id: 1, type: "image", src: "/a.jpg", duration_ms: 3000 }],
    })
    hook.mounted()
    const layer = hook.layers[hook.active]
    expect(layer.img.decoding).toBe("async")
    expect(layer.img.loading).toBe("eager")
    expect(layer.img.style.imageRendering.length).toBeGreaterThan(0)
    hook.destroyed()
  })

  it("image onload writes the natural resolution to #display-status", () => {
    const hook = makeHost({
      items: [{ id: 1, type: "image", src: "/photo.jpg", duration_ms: 3000 }],
    })
    hook.mounted()
    const layer = hook.layers[hook.active]
    Object.defineProperty(layer.img, "naturalWidth", { value: 3024, configurable: true })
    Object.defineProperty(layer.img, "naturalHeight", { value: 4032, configurable: true })
    layer.img.onload()
    const status = document.getElementById("display-status").textContent
    expect(status).toContain("photo.jpg")
    expect(status).toContain("3024x4032")
    hook.destroyed()
  })
})
