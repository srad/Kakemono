import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"

// ---------------------------------------------------------------------------
// GridStack mock — simulates real GridStack behaviour:
//   - adds gs-id-N class to the container
//   - injects a <style> into el.parentNode (the bug) OR <head> (with styleInHead)
// ---------------------------------------------------------------------------
let fakeGrid
let gridInitEl
let capturedStyleLocation

vi.mock("gridstack", () => ({
  GridStack: {
    init: vi.fn((opts, el) => {
      gridInitEl = el
      el.classList.add("gs-id-1", "grid-stack-initialized")

      // Replicate GridStack's actual style injection logic
      const styleLocation = opts.styleInHead ? document.head : el.parentNode
      capturedStyleLocation = styleLocation
      const style = document.createElement("style")
      style.setAttribute("data-gs-id", "gs-id-1")
      style.textContent = ".gs-id-1 > .grid-stack-item { height: 50px; } " +
        ".gs-id-1 > .grid-stack-item > .grid-stack-item-content { top:8px;right:8px;bottom:8px;left:8px; }"
      styleLocation.appendChild(style)

      fakeGrid = {
        float: vi.fn(),
        on: vi.fn(),
        cellHeight: vi.fn(),
        _updateStyles: vi.fn(),
        engine: { nodes: [] },
        addWidget: vi.fn((opts) => {
          const item = document.createElement("div")
          item.className = "grid-stack-item"
          item.gridstackNode = {}
          el.appendChild(item)
          return item
        }),
        removeWidget: vi.fn(),
        destroy: vi.fn(),
      }
      return fakeGrid
    }),
  },
}))

import GridEditor from "../js/hooks/grid_editor.js"

// ---------------------------------------------------------------------------
// Helper: build a mounted hook with a real DOM frame + canvas element.
// jsdom returns 0 for clientWidth/clientHeight unless forced.
// ---------------------------------------------------------------------------
function makeHost(cells = [], opts = {}) {
  const frame = document.createElement("div")
  Object.defineProperty(frame, "clientWidth", { get: () => 800, configurable: true })
  Object.defineProperty(frame, "clientHeight", { get: () => 600, configurable: true })

  const el = document.createElement("div")
  el.id = "grid-canvas"
  el.dataset.cells = JSON.stringify(cells)
  el.dataset.aspectRatio = opts.aspectRatio || "9:16"
  el.dataset.orientation = opts.orientation || "portrait"
  el.dataset.colorScheme = opts.colorScheme || "light"
  el.className = "grid-stack dashboard-editor-surface"

  frame.appendChild(el)
  document.body.appendChild(frame)

  const hook = Object.create(GridEditor)
  hook.el = el
  hook.pushEvent = vi.fn()
  hook.handleEvent = vi.fn()
  return hook
}

// Simulate what LiveView does when it patches the dashboard-editor-frame:
// removes any child elements that weren't in the original server-rendered
// template (LiveView only knows about #grid-canvas as a child).
function simulateLiveViewPatchFrame(frame, gridCanvas) {
  // LiveView removes children it doesn't recognise — i.e. everything except
  // the known #grid-canvas element (and phx-update="ignore" protects grid-canvas
  // children, but the frame itself is patched normally).
  for (const child of [...frame.children]) {
    if (child !== gridCanvas) child.remove()
  }
}

// Simulate what LiveView does to the #grid-canvas element itself:
// only data-* attributes are updated; class and style are preserved.
function simulateLiveViewPatchCanvas(el) {
  // data-* attributes are updated (e.g. data-cells refreshed) — simulate
  // by touching one data attribute; class/style are left alone.
  el.dataset.cells = el.dataset.cells  // no-op but represents the patch
}

describe("GridEditor hook", () => {
  beforeEach(() => {
    fakeGrid = undefined
    gridInitEl = undefined
    vi.clearAllMocks()
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  // -------------------------------------------------------------------------
  // mount
  // -------------------------------------------------------------------------
  it("mounted() sets inline width/height/css-vars on the element", () => {
    const hook = makeHost()
    hook.mounted()

    expect(hook.el.style.width).toMatch(/\d+px/)
    expect(hook.el.style.height).toMatch(/\d+px/)
    expect(hook.el.style.getPropertyValue("--dashboard-cell-width")).toMatch(/\d/)
    expect(hook.el.style.getPropertyValue("--dashboard-cell-height")).toMatch(/\d/)
  })

  it("mounted() stores _lastBoard so updated() can restore styles", () => {
    const hook = makeHost()
    hook.mounted()
    expect(hook._lastBoard).toBeTruthy()
    expect(hook._lastBoard.width).toBeGreaterThan(0)
    expect(hook._lastBoard.height).toBeGreaterThan(0)
  })

  // -------------------------------------------------------------------------
  // THE ACTUAL BUG: GridStack injects <style> into el.parentNode by default.
  // LiveView patches the parent frame and removes unknown children → style gone.
  // -------------------------------------------------------------------------
  it("styleInHead:true — GridStack injects <style> into <head>, not parentNode", () => {
    const hook = makeHost()
    hook.mounted()

    // Style must be in <head>, not in the frame div
    expect(capturedStyleLocation).toBe(document.head)
    const styleInFrame = hook.el.parentElement.querySelector("style[data-gs-id]")
    expect(styleInFrame).toBeNull()
  })

  it("LiveView patching the frame does NOT remove GridStack stylesheet from <head>", () => {
    const hook = makeHost()
    hook.mounted()

    const stylesBefore = document.head.querySelectorAll("style[data-gs-id]").length
    expect(stylesBefore).toBeGreaterThan(0)

    // Simulate LiveView removing injected children from the frame
    simulateLiveViewPatchFrame(hook.el.parentElement, hook.el)
    hook.updated()

    const stylesAfter = document.head.querySelectorAll("style[data-gs-id]").length
    expect(stylesAfter).toBe(stylesBefore) // stylesheet survives
  })

  it("without styleInHead, LiveView patch removes GridStack stylesheet (documents the bug)", () => {
    // GridStack injects <style> into el.parentNode by default.
    // LiveView patches the frame div and removes children not in the template.
    const frame = document.createElement("div")
    const el = document.createElement("div")
    frame.appendChild(el)
    document.body.appendChild(frame)

    // Inject a style as GridStack would without styleInHead
    const style = document.createElement("style")
    style.setAttribute("data-gs-id", "gs-id-bug")
    frame.appendChild(style)

    expect(frame.querySelector("style[data-gs-id]")).not.toBeNull()

    // LiveView removes frame children it doesn't know about
    simulateLiveViewPatchFrame(frame, el)

    // Style is gone — this is exactly the bug
    expect(frame.querySelector("style[data-gs-id]")).toBeNull()
  })

  it("updated() does NOT call grid.cellHeight() (no GridStack re-layout)", () => {
    const hook = makeHost()
    hook.mounted()
    fakeGrid.cellHeight.mockClear()

    simulateLiveViewPatchCanvas(hook.el)
    hook.updated()

    expect(fakeGrid.cellHeight).not.toHaveBeenCalled()
  })

  // -------------------------------------------------------------------------
  // dragstop / resizestop → savePositions
  // -------------------------------------------------------------------------
  it("dragstop fires pushEvent with correct widget positions", () => {
    const hook = makeHost()
    hook.mounted()

    fakeGrid.engine.nodes = [
      { _widgetId: 42, x: 0, y: 3, w: 4, h: 2 },
      { _widgetId: 99, x: 4, y: 0, w: 6, h: 3 },
    ]

    // Retrieve the dragstop/resizestop handler registered via grid.on()
    const [eventName, handler] = fakeGrid.on.mock.calls.find(([name]) =>
      name.includes("dragstop"),
    )
    handler()

    expect(hook.pushEvent).toHaveBeenCalledWith("cells_changed", {
      cells: [
        { widget_instance_id: 42, x: 0, y: 3, w: 4, h: 2 },
        { widget_instance_id: 99, x: 4, y: 0, w: 6, h: 3 },
      ],
    })
  })

  it("dragstop skips nodes without _widgetId", () => {
    const hook = makeHost()
    hook.mounted()

    fakeGrid.engine.nodes = [
      { _widgetId: null, x: 0, y: 0, w: 2, h: 2 },
      { _widgetId: 7, x: 2, y: 0, w: 2, h: 2 },
    ]

    const [, handler] = fakeGrid.on.mock.calls.find(([name]) => name.includes("dragstop"))
    handler()

    expect(hook.pushEvent).toHaveBeenCalledWith("cells_changed", {
      cells: [{ widget_instance_id: 7, x: 2, y: 0, w: 2, h: 2 }],
    })
  })

  // -------------------------------------------------------------------------
  // destroyed()
  // -------------------------------------------------------------------------
  it("destroyed() calls grid.destroy(false)", () => {
    const hook = makeHost()
    hook.mounted()
    hook.destroyed()
    expect(fakeGrid.destroy).toHaveBeenCalledWith(false)
  })
})
