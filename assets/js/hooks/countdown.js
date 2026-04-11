const Countdown = {
  mounted() {
    this._animId = null
    this._frozen = false
    this._start()
  },

  updated() {
    this._stop()
    this._start()
  },

  destroyed() {
    this._stop()
  },

  _start() {
    const status = this.el.dataset.status
    if (status === "paused") {
      this._frozen = true
      return
    }
    this._frozen = false

    const nextPickAt = parseInt(this.el.dataset.nextPickAt, 10)
    const serverNow = parseInt(this.el.dataset.serverNow, 10)

    if (!nextPickAt || !serverNow) return

    const totalMs = nextPickAt - serverNow
    if (totalMs <= 0) {
      this._renderArc(0, 0)
      return
    }

    const clientStart = performance.now()
    const tick = (now) => {
      if (this._frozen) return

      const elapsed = now - clientStart
      const remainingMs = Math.max(0, totalMs - elapsed)
      const fraction = remainingMs / totalMs
      const seconds = Math.ceil(remainingMs / 1000)

      this._renderArc(fraction, seconds)

      if (remainingMs > 0) {
        this._animId = requestAnimationFrame(tick)
      }
    }

    this._animId = requestAnimationFrame(tick)
  },

  _stop() {
    if (this._animId) {
      cancelAnimationFrame(this._animId)
      this._animId = null
    }
  },

  _renderArc(fraction, seconds) {
    const svg = this.el.querySelector("svg circle.countdown-arc")
    const text = this.el.querySelector(".countdown-text")

    if (svg) {
      const r = parseFloat(svg.getAttribute("r")) || 18
      const circumference = 2 * Math.PI * r
      const offset = circumference * (1 - fraction)
      svg.style.strokeDasharray = `${circumference}`
      svg.style.strokeDashoffset = `${offset}`
    }

    if (text) {
      text.textContent = seconds
    }
  },
}

export default Countdown
