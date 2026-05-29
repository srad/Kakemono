import { describe, it, expect, vi } from "vitest"
import { bindFullyKioskEvents, runFullyKioskCommand } from "../js/fully_kiosk.js"

describe("Fully Kiosk command bridge", () => {
  it("calls Fully Kiosk commands when available", () => {
    const reloadPage = vi.fn()
    const win = { fully: { reloadPage }, location: { reload: vi.fn() } }

    runFullyKioskCommand("reloadPage", win)

    expect(reloadPage).toHaveBeenCalledOnce()
    expect(win.location.reload).not.toHaveBeenCalled()
  })

  it("falls back to window reload for reloadPage in regular browsers", () => {
    const win = { location: { reload: vi.fn() } }

    runFullyKioskCommand("reloadPage", win)

    expect(win.location.reload).toHaveBeenCalledOnce()
  })

  it("ignores unsupported commands in regular browsers", () => {
    const win = { location: { reload: vi.fn() } }

    runFullyKioskCommand("screenOn", win)

    expect(win.location.reload).not.toHaveBeenCalled()
  })

  it("binds the phx:fully_kiosk event", () => {
    const listeners = {}
    const win = {
      addEventListener: (name, callback) => {
        listeners[name] = callback
      },
      location: { reload: vi.fn() },
    }

    bindFullyKioskEvents(win)
    listeners["phx:fully_kiosk"]({ detail: { cmd: "reloadPage" } })

    expect(win.location.reload).toHaveBeenCalledOnce()
  })
})
