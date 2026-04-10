const AutoDismiss = {
  mounted() {
    this._timeout = setTimeout(() => {
      this.el.classList.add("opacity-0", "transition-opacity", "duration-300")
      // Remove from DOM after fade-out transition
      setTimeout(() => {
        this.el.remove()
      }, 300)
    }, 4000)
  },

  destroyed() {
    if (this._timeout) {
      clearTimeout(this._timeout)
    }
  },
}

export default AutoDismiss
