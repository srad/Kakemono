// LocationSearch hook — autocomplete city/place names via Open-Meteo geocoding.
// Writes the chosen result's latitude/longitude into hidden inputs
// `config[latitude]` and `config[longitude]` within the enclosing <form>.

const ENDPOINT = "https://geocoding-api.open-meteo.com/v1/search"
const DEBOUNCE_MS = 300

const LocationSearch = {
  mounted() {
    this.input = this.el.querySelector(".kw-loc-input")
    this.list = this.el.querySelector(".kw-loc-results")
    this.form = this.el.closest("form")
    this.timer = null
    this.lastQuery = ""

    this._onInput = (e) => this.scheduleSearch(e.target.value)
    this._onFocus = () => {
      if (this.list.children.length > 0) this.list.classList.add("kw-loc-open")
    }
    this._onBlur = () => {
      // Delay so a click on a result item lands before we hide the list.
      setTimeout(() => this.list.classList.remove("kw-loc-open"), 150)
    }
    this._onDocClick = (e) => {
      if (!this.el.contains(e.target)) this.list.classList.remove("kw-loc-open")
    }

    this.input.addEventListener("input", this._onInput)
    this.input.addEventListener("focus", this._onFocus)
    this.input.addEventListener("blur", this._onBlur)
    document.addEventListener("click", this._onDocClick)
  },

  destroyed() {
    clearTimeout(this.timer)
    this.input?.removeEventListener("input", this._onInput)
    this.input?.removeEventListener("focus", this._onFocus)
    this.input?.removeEventListener("blur", this._onBlur)
    document.removeEventListener("click", this._onDocClick)
  },

  scheduleSearch(query) {
    clearTimeout(this.timer)
    const q = (query || "").trim()
    if (q.length < 2) {
      this.renderResults([])
      return
    }
    if (q === this.lastQuery) return
    this.timer = setTimeout(() => this.runSearch(q), DEBOUNCE_MS)
  },

  async runSearch(q) {
    this.lastQuery = q
    const url = `${ENDPOINT}?name=${encodeURIComponent(q)}&count=8&language=en&format=json`
    try {
      const res = await fetch(url, { headers: { "Accept": "application/json" } })
      if (!res.ok) {
        this.renderError(`Lookup failed (${res.status})`)
        return
      }
      const data = await res.json()
      this.renderResults(data.results || [])
    } catch (_err) {
      this.renderError("Network error")
    }
  },

  renderResults(results) {
    this.list.innerHTML = ""
    if (!results.length) {
      this.list.classList.remove("kw-loc-open")
      return
    }
    for (const r of results) {
      const li = document.createElement("li")
      li.className = "kw-loc-item"
      li.textContent = this.formatResult(r)
      li.addEventListener("mousedown", (e) => {
        // mousedown fires before blur, ensuring selection works.
        e.preventDefault()
        this.choose(r)
      })
      this.list.appendChild(li)
    }
    this.list.classList.add("kw-loc-open")
  },

  renderError(msg) {
    this.list.innerHTML = `<li class="kw-loc-item kw-loc-error">${msg}</li>`
    this.list.classList.add("kw-loc-open")
  },

  formatResult(r) {
    return [r.name, r.admin1, r.country].filter(Boolean).join(", ")
  },

  choose(r) {
    const display = this.formatResult(r)
    this.input.value = display

    const latInput = this.form?.querySelector('input[name="config[latitude]"]')
    const lonInput = this.form?.querySelector('input[name="config[longitude]"]')
    if (latInput) latInput.value = r.latitude
    if (lonInput) lonInput.value = r.longitude

    this.list.classList.remove("kw-loc-open")
    this.list.innerHTML = ""
  },
}

export default LocationSearch
