import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"

// Capture constructor arguments and expose the onEnd callback.
let lastInstance
vi.mock("sortablejs", () => {
  return {
    default: class FakeSortable {
      constructor(el, opts) {
        this.el = el
        this.opts = opts
        this.destroy = vi.fn()
        lastInstance = this
      }
    },
  }
})

import SortableHook from "../js/hooks/sortable.js"

function makeHost(ids = ["1", "2", "3"]) {
  document.body.innerHTML = `<ul id="list">${ids
    .map((id) => `<li data-id="${id}">${id}</li>`)
    .join("")}</ul>`
  const el = document.getElementById("list")
  const hook = Object.create(SortableHook)
  hook.el = el
  hook.pushEvent = vi.fn()
  return hook
}

describe("Sortable hook", () => {
  beforeEach(() => {
    lastInstance = undefined
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("mounted() instantiates Sortable with animation + ghostClass", () => {
    const hook = makeHost()
    hook.mounted()
    expect(lastInstance).toBeTruthy()
    expect(lastInstance.opts.animation).toBe(150)
    expect(lastInstance.opts.ghostClass).toBe("opacity-40")
  })

  it("onEnd pushes 'reorder' with current child data-ids in order", () => {
    const hook = makeHost(["a", "b", "c"])
    hook.mounted()
    // Simulate a manual reorder: move first child to the end.
    const first = hook.el.firstElementChild
    hook.el.appendChild(first)
    lastInstance.opts.onEnd()
    expect(hook.pushEvent).toHaveBeenCalledWith("reorder", {
      ids: ["b", "c", "a"],
    })
  })

  it("onEnd filters out children without data-id", () => {
    const hook = makeHost(["a", "b"])
    const stray = document.createElement("li")
    hook.el.appendChild(stray)
    hook.mounted()
    lastInstance.opts.onEnd()
    expect(hook.pushEvent).toHaveBeenCalledWith("reorder", {
      ids: ["a", "b"],
    })
  })

  it("destroyed() calls sortable.destroy()", () => {
    const hook = makeHost()
    hook.mounted()
    hook.destroyed()
    expect(lastInstance.destroy).toHaveBeenCalled()
  })

  it("destroyed() is safe before mounted()", () => {
    const hook = makeHost()
    expect(() => hook.destroyed()).not.toThrow()
  })
})
