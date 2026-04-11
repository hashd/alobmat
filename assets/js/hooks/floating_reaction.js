const FloatingReaction = {
  mounted() {
    this._reactions = []

    this.handleEvent("reaction", ({ emoji }) => {
      this._spawnReaction(emoji)
    })
  },

  destroyed() {
    this._reactions.forEach((span) => span.remove())
    this._reactions = []
  },

  _spawnReaction(emoji) {
    // Cap at 20 active reactions
    if (this._reactions.length >= 20) {
      const oldest = this._reactions.shift()
      oldest.remove()
    }

    const span = document.createElement("span")
    span.textContent = emoji
    span.className = "animate-float-up absolute text-2xl pointer-events-none"
    span.style.left = `${10 + Math.random() * 80}%`
    span.style.bottom = "0"

    this.el.appendChild(span)
    this._reactions.push(span)

    const onEnd = () => {
      span.removeEventListener("animationend", onEnd)
      span.remove()
      const idx = this._reactions.indexOf(span)
      if (idx !== -1) this._reactions.splice(idx, 1)
    }

    span.addEventListener("animationend", onEnd)

    // Fallback removal after 2.5s in case animationend doesn't fire
    setTimeout(() => {
      if (span.parentNode) {
        span.remove()
        const idx = this._reactions.indexOf(span)
        if (idx !== -1) this._reactions.splice(idx, 1)
      }
    }, 2500)
  },
}

export default FloatingReaction
