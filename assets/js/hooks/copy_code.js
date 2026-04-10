const CopyCode = {
  mounted() {
    this._onClick = async () => {
      const code = this.el.dataset.code || ""

      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(code)
        } else {
          this._fallbackCopy(code)
        }
        this._showTooltip()
      } catch (_err) {
        // Try fallback on clipboard API failure
        try {
          this._fallbackCopy(code)
          this._showTooltip()
        } catch (_fallbackErr) {
          // Silently fail
        }
      }
    }

    this.el.addEventListener("click", this._onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    if (this._timeout) clearTimeout(this._timeout)
  },

  _fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.style.position = "fixed"
    textarea.style.left = "-9999px"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    document.body.removeChild(textarea)
  },

  _showTooltip() {
    this.el.classList.add("copied")
    if (this._timeout) clearTimeout(this._timeout)
    this._timeout = setTimeout(() => {
      this.el.classList.remove("copied")
    }, 1500)
  },
}

export default CopyCode
