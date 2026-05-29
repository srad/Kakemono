import { GridStack } from "gridstack"

// GridStack v11+ stopped rendering a widget's `content` as HTML by default
// (XSS hardening) — it now sets textContent, which made our widget cards show
// as raw escaped markup. We build trusted HTML here, so restore innerHTML
// rendering via the global render callback.
GridStack.renderCB = (el, widget) => {
  el.innerHTML = widget.content || ""
}

const COLUMNS = 12
const ROWS = 12

const WIDGET_META = {
  clock:     { icon: "🕐", name: "Clock" },
  weather:   { icon: "🌤", name: "Weather" },
  slideshow: { icon: "🖼", name: "Slideshow" },
  rss:       { icon: "📰", name: "Feed" },
  instagram: { icon: "📸", name: "Instagram" },
}

function widgetBody(type) {
  switch (type) {
    case "clock":
      return `
        <div class="wi-body">
          <div class="wi-clock">
            <div class="wi-clock-digits">12:00</div>
            <div class="wi-clock-date">Wed 26</div>
          </div>
        </div>`

    case "weather":
      return `
        <div class="wi-body">
          <div class="wi-weather">
            <div class="wi-weather-emoji">🌤</div>
            <div class="wi-weather-info">
              <span class="wi-temp">—°</span>
              <span class="wi-condition">Weather</span>
            </div>
          </div>
        </div>`

    case "slideshow":
      return `
        <div class="wi-body">
          <div class="wi-slides">
            <div class="wi-slide wi-slide-3"></div>
            <div class="wi-slide wi-slide-2"></div>
            <div class="wi-slide wi-slide-1"><span class="wi-play">▶</span></div>
          </div>
        </div>`

    case "instagram":
      return `
        <div class="wi-body">
          <div class="wi-slides">
            <div class="wi-slide wi-slide-3"></div>
            <div class="wi-slide wi-slide-2"></div>
            <div class="wi-slide wi-slide-1"><span class="wi-play">📸</span></div>
          </div>
        </div>`

    case "rss":
      return `
        <div class="wi-body">
          <div class="wi-rss">
            <div class="wi-rss-header">
              <span class="wi-rss-icon">📰</span>
              <span class="wi-rss-title">Feed</span>
            </div>
            <div class="wi-rss-lines">
              <div class="wi-line" style="width:92%"></div>
              <div class="wi-line" style="width:72%"></div>
              <div class="wi-line wi-line-sep" style="width:86%"></div>
              <div class="wi-line" style="width:68%"></div>
            </div>
          </div>
        </div>`

    default:
      return `<div class="wi-body"><div class="wi-generic">▪</div></div>`
  }
}

function makeCard(cell) {
  const { icon, name } = WIDGET_META[cell.type] || { icon: "▪", name: cell.type }
  const id = cell.widget_instance_id
  return `
    <div class="widget-card widget-${cell.type} group select-none dashboard-widget-preview">
      <div class="widget-drag-body cursor-move">
        ${widgetBody(cell.type)}
        <div class="widget-badge">
          <span class="wi-icon">${icon}</span>
          <span class="wi-name">${name}</span>
          <span class="wi-id">#${id}</span>
        </div>
      </div>
      <div class="widget-actions">
        <button class="js-config widget-action-btn" data-widget-id="${id}" title="Configure" aria-label="Configure">
          <span class="hero-cog-6-tooth-micro h-4 w-4"></span>
        </button>
        <button class="js-remove widget-action-btn widget-action-del" data-widget-id="${id}" title="Remove" aria-label="Remove">
          <span class="hero-x-mark-micro h-4 w-4"></span>
        </button>
      </div>
    </div>`
}

function parseAspectRatio(value, orientation = "portrait") {
  const [rawWidth, rawHeight] = String(value || "16:9").split(":")
  let width = Number(rawWidth)
  let height = Number(rawHeight)

  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    width = 16
    height = 9
  }

  if (orientation === "portrait" && width > height) {
    ;[width, height] = [height, width]
  } else if (orientation === "landscape" && height > width) {
    ;[width, height] = [height, width]
  }

  return width / height
}

const GridEditor = {
  mounted() {
    const cells = JSON.parse(this.el.dataset.cells || "[]")
    const frame = this.el.parentElement
    const orientation = this.el.dataset.orientation || "portrait"
    const colorScheme = this.el.dataset.colorScheme || "light"
    const aspectRatio = parseAspectRatio(this.el.dataset.aspectRatio, orientation)

    this.el.dataset.colorScheme = colorScheme
    this.el.dataset.orientation = orientation

    const measureBoard = () => {
      const frameWidth = frame?.clientWidth || this.el.parentElement?.clientWidth || window.innerWidth
      const frameHeight =
        frame?.clientHeight || Math.max(360, window.innerHeight - 180)
      const availableWidth = Math.max(240, frameWidth - 32)
      const availableHeight = Math.max(240, frameHeight - 32)

      let width = availableWidth
      let height = width / aspectRatio

      if (height > availableHeight) {
        height = availableHeight
        width = height * aspectRatio
      }

      return {
        width: Math.floor(width),
        height: Math.floor(height),
        cellHeight: height / ROWS,
      }
    }

    const applyStyles = (board) => {
      this.el.style.width = `${board.width}px`
      this.el.style.height = `${board.height}px`
      this.el.style.setProperty("--dashboard-cell-width", `${board.width / COLUMNS}px`)
      this.el.style.setProperty("--dashboard-cell-height", `${board.cellHeight}px`)
    }

    const applyBoardSize = () => {
      const board = measureBoard()
      applyStyles(board)
      this._lastBoard = board

      if (this.grid) {
        this.grid.cellHeight(board.cellHeight, true)
        this.grid._updateStyles?.(true, ROWS)
      }

      return board
    }

    this._applyStyles = applyStyles
    const initialBoard = applyBoardSize()

    const classesBeforeInit = new Set(this.el.className.split(" ").filter(Boolean))

    this.grid = GridStack.init(
      {
        column: COLUMNS,
        row: ROWS,
        cellHeight: initialBoard.cellHeight,
        animate: false,
        float: true,
        styleInHead: true,
        alwaysShowResizeHandle: true,
        resizable: { handles: "n,e,s,w,ne,se,sw,nw" },
        draggable: { handle: ".cursor-move" },
        margin: 8,
      },
      this.el
    )

    this._gridstackClasses = this.el.className
      .split(" ")
      .filter((c) => c && !classesBeforeInit.has(c))

    this.grid.float(true)
    this.grid._updateStyles?.(true, ROWS)
    cells.forEach((cell) => this._addWidget(cell))

    const savePositions = () => {
      const payload = this.grid.engine.nodes
        .filter((node) => node._widgetId != null)
        .map((node) => ({
          widget_instance_id: node._widgetId,
          x: node.x,
          y: node.y,
          w: node.w,
          h: node.h,
        }))
      if (payload.length > 0) this.pushEvent("cells_changed", { cells: payload })
    }
    this.grid.on("dragstop resizestop", savePositions)

    const syncGridSize = () => {
      applyBoardSize()
    }

    if (typeof ResizeObserver !== "undefined" && frame) {
      this._resizeObserver = new ResizeObserver(() => {
        if (this._resizeFrame) window.cancelAnimationFrame(this._resizeFrame)
        this._resizeFrame = window.requestAnimationFrame(syncGridSize)
      })
      this._resizeObserver.observe(frame)
    } else {
      window.addEventListener("resize", syncGridSize)
      this._resizeFallback = syncGridSize
    }


    this.el.addEventListener("click", (e) => {
      const configBtn = e.target.closest(".js-config")
      const removeBtn = e.target.closest(".js-remove")
      if (configBtn) {
        e.stopPropagation()
        this.pushEvent("open_config", {
          widget_instance_id: parseInt(configBtn.dataset.widgetId),
        })
      } else if (removeBtn) {
        e.stopPropagation()
        this.pushEvent("remove_from_canvas", {
          widget_instance_id: parseInt(removeBtn.dataset.widgetId),
        })
      }
    })

    this.handleEvent("grid_add_widget", ({ cell }) => {
      this._addWidget(cell)
    })

    this.handleEvent("grid_remove_widget", ({ widget_instance_id }) => {
      const el = this.el.querySelector(
        `.grid-stack-item[data-widget-id="${widget_instance_id}"]`
      )
      if (el) this.grid.removeWidget(el, true)
    })
  },

  updated() {
    if (this._gridstackClasses?.length) {
      this._gridstackClasses.forEach((c) => this.el.classList.add(c))
    }
    if (this._lastBoard) this._applyStyles(this._lastBoard)
  },

  destroyed() {
    if (this._resizeFrame) window.cancelAnimationFrame(this._resizeFrame)
    if (this._resizeObserver) this._resizeObserver.disconnect()
    if (this._resizeFallback) {
      window.removeEventListener("resize", this._resizeFallback)
    }
    if (this.grid) this.grid.destroy(false)
  },

  _addWidget(cell) {
    const el = this.grid.addWidget({
      x: cell.x,
      y: cell.y,
      w: cell.w,
      h: cell.h,
      minW: 1,
      minH: 1,
      maxW: COLUMNS,
      maxH: ROWS,
      content: makeCard(cell),
    })
    el.dataset.widgetId = String(cell.widget_instance_id)
    if (el.gridstackNode) el.gridstackNode._widgetId = cell.widget_instance_id
  },
}

export default GridEditor
