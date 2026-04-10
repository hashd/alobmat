const Presence = {
  mounted() {
    this._awayTimer = null

    this._onVisibilityChange = () => {
      if (document.hidden) {
        this._awayTimer = setTimeout(() => {
          this.pushEvent("away", {})
        }, 30000)
      } else {
        if (this._awayTimer) {
          clearTimeout(this._awayTimer)
          this._awayTimer = null
        }
        this.pushEvent("online", {})
      }
    }

    document.addEventListener("visibilitychange", this._onVisibilityChange)
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this._onVisibilityChange)
    if (this._awayTimer) {
      clearTimeout(this._awayTimer)
      this._awayTimer = null
    }
  },
}

export default Presence
