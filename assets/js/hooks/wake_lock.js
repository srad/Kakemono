// Keeps the screen awake on display devices (kiosk browsers) using the Screen
// Wake Lock API. The lock is released by the browser whenever the page becomes
// hidden (tab switch, screen off by other means), so we re-acquire it on
// visibilitychange.
//
// Caveats:
//   - The Wake Lock API requires a secure context: HTTPS, or http://localhost.
//     Over plain HTTP on a LAN IP it is unavailable (navigator.wakeLock is
//     undefined) — in that case this hook is a no-op and you should rely on the
//     kiosk browser's own "keep screen on" setting.
//   - Some platforms only honor the lock while the tab is visible/focused.
const WakeLock = {
  mounted() {
    this._sentinel = null

    this._acquire = async () => {
      if (!("wakeLock" in navigator)) return
      if (document.visibilityState !== "visible") return
      if (this._sentinel) return

      try {
        this._sentinel = await navigator.wakeLock.request("screen")
        this._sentinel.addEventListener("release", () => {
          this._sentinel = null
        })
      } catch (err) {
        // NotAllowedError (e.g. insecure context or blocked) — give up quietly.
        this._sentinel = null
      }
    }

    this._onVisibility = () => {
      if (document.visibilityState === "visible") this._acquire()
    }

    document.addEventListener("visibilitychange", this._onVisibility)
    this._acquire()
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this._onVisibility)
    if (this._sentinel) {
      this._sentinel.release().catch(() => {})
      this._sentinel = null
    }
  },
}

export default WakeLock
