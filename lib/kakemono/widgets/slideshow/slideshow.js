// Slideshow hook for fullscreen displays.
// Exported as a plain object so it can be tested without the
// phoenix_live_view runtime — vitest in jsdom can call mounted()/show()
// directly on a stand-in `this` (see test/slideshow.test.js).

const Slideshow = {
  mounted() {
    this.rawFitMode = this.el.dataset.fitMode || ""
    this.fitMode = this.normalizeFitMode(this.rawFitMode)
    this.layers = [this.makeLayer(), this.makeLayer()]
    this.el.appendChild(this.layers[0].root)
    this.el.appendChild(this.layers[1].root)
    this.active = 0
    this.index = 0
    const parsed = this.parseItems()
    this.rawItems = parsed.raw
    this.items = parsed.items
    this.instanceId = this.el.dataset.instanceId ? parseInt(this.el.dataset.instanceId, 10) : null
    this.timer = null
    this.requestWakeLock()
    this.flashStatus("connected · " + this.items.length + " items · " + this.fitMode)

    if (typeof this.handleEvent === "function") {
      this.handleEvent("slideshow:update", ({ instance_id, items, fit_mode }) => {
        if (instance_id != null && this.instanceId != null && instance_id !== this.instanceId) return
        this.items = Array.isArray(items) ? items : []
        this.index = 0
        if (fit_mode) this.applyFitMode(fit_mode)
        this.show()
      })
    }

    this._visibilityHandler = () => {
      if (document.visibilityState === "visible") this.requestWakeLock()
    }
    document.addEventListener("visibilitychange", this._visibilityHandler)

    this.show()
  },

  updated() {
    const layersChanged = this.ensureLayers()
    const dataChanged = this.syncFromDataset()
    if (layersChanged || dataChanged) this.show()
  },

  destroyed() {
    clearTimeout(this.timer)
    if (this._visibilityHandler) {
      document.removeEventListener("visibilitychange", this._visibilityHandler)
    }
    if (this.wakeLock) this.wakeLock.release().catch(() => {})
  },

  flashStatus(text) {
    const el = document.getElementById("display-status")
    if (el) el.textContent = text
  },

  normalizeFitMode(raw) {
    return raw || "contain"
  },

  parseItems() {
    const raw = this.el.dataset.items || "[]"

    try {
      const items = JSON.parse(raw)
      return { raw, items: Array.isArray(items) ? items : [] }
    } catch (_err) {
      return { raw, items: [] }
    }
  },

  syncFromDataset() {
    let changed = false

    const parsed = this.parseItems()
    if (parsed.raw !== this.rawItems) {
      this.rawItems = parsed.raw
      this.items = parsed.items
      this.index = 0
      changed = true
    }

    const rawFitMode = this.el.dataset.fitMode || ""
    if (rawFitMode !== this.rawFitMode) {
      this.rawFitMode = rawFitMode
      this.applyFitMode(this.normalizeFitMode(rawFitMode))
      changed = true
    }

    return changed
  },

  ensureLayers() {
    let changed = false

    if (!Array.isArray(this.layers) || this.layers.length !== 2) {
      this.layers = [this.makeLayer(), this.makeLayer()]
      this.active = 0
      changed = true
    }

    this.layers.forEach((layer, idx) => {
      if (!layer?.root || !layer.img || !layer.vid) {
        this.layers[idx] = this.makeLayer()
        layer = this.layers[idx]
        changed = true
      }

      if (layer.root.parentElement !== this.el) {
        this.el.appendChild(layer.root)
        changed = true
      }
    })

    if (!Number.isInteger(this.active) || this.active < 0 || this.active >= this.layers.length) {
      this.active = 0
      changed = true
    }

    return changed
  },

  async requestWakeLock() {
    try {
      if (typeof navigator !== "undefined" && "wakeLock" in navigator) {
        this.wakeLock = await navigator.wakeLock.request("screen")
      }
    } catch (_) {}
  },

  makeLayer() {
    const root = document.createElement("div")
    root.style.cssText =
      "position:absolute;inset:0;opacity:0;transition:opacity 600ms ease-in-out;"
    const img = document.createElement("img")
    img.decoding = "async"
    img.loading = "eager"
    img.style.cssText =
      `width:100%;height:100%;object-fit:${this.fitMode};display:none;` +
      `image-rendering:high-quality;image-rendering:-webkit-optimize-contrast;`
    const vid = document.createElement("video")
    vid.style.cssText = `width:100%;height:100%;object-fit:${this.fitMode};display:none;`
    vid.muted = true
    vid.playsInline = true
    vid.preload = "auto"
    root.appendChild(img)
    root.appendChild(vid)
    return { root, img, vid }
  },

  applyFitMode(mode) {
    this.fitMode = this.normalizeFitMode(mode)
    if (!this.layers) return
    this.layers.forEach((l) => {
      l.img.style.objectFit = this.fitMode
      l.vid.style.objectFit = this.fitMode
    })
  },

  show() {
    clearTimeout(this.timer)
    if (!this.items.length) {
      this.layers.forEach((l) => (l.root.style.opacity = "0"))
      return
    }
    const item = this.items[this.index % this.items.length]
    const next = (this.active + 1) % 2
    const layer = this.layers[next]

    if (item.type === "video") {
      layer.img.style.display = "none"
      layer.vid.style.display = "block"
      layer.vid.src = item.src
      layer.vid.currentTime = 0
      const p = layer.vid.play()
      if (p && typeof p.catch === "function") p.catch(() => {})
    } else {
      layer.vid.pause()
      layer.vid.removeAttribute("src")
      layer.vid.load()
      layer.vid.style.display = "none"
      layer.img.style.display = "block"
      layer.img.onerror = () => this.flashStatus("error loading " + item.src)
      layer.img.onload = () => {
        this.flashStatus(
          item.src.split("/").pop() +
            " · " + layer.img.naturalWidth + "x" + layer.img.naturalHeight +
            " · fit:" + this.fitMode
        )
      }
      layer.img.src = item.src
    }

    this.layers[this.active].root.style.opacity = "0"
    layer.root.style.opacity = "1"
    this.active = next

    const dur = Math.max(2000, item.duration_ms || 6000)
    this.timer = setTimeout(() => {
      this.index = (this.index + 1) % this.items.length
      this.show()
    }, dur)
  },
}

export default Slideshow
