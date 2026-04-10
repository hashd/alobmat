const BoardSheet = {
  mounted() {
    this._touchStartY = 0
    this._currentTranslateY = 0
    this._sheetHeight = 0

    this.handleEvent("open-board-sheet", () => {
      this._open()
    })

    this.handleEvent("close-board-sheet", () => {
      this._close()
    })

    // Backdrop click closes the sheet
    this._onBackdropClick = (e) => {
      if (e.target === this.el) {
        this._close()
      }
    }
    this.el.addEventListener("click", this._onBackdropClick)

    // Close button
    const closeBtn = this.el.querySelector("[data-close-sheet]")
    if (closeBtn) {
      this._onCloseClick = () => this._close()
      closeBtn.addEventListener("click", this._onCloseClick)
    }

    // Touch drag on handle
    const handle = this.el.querySelector("[data-drag-handle]")
    if (handle) {
      this._onTouchStart = (e) => {
        this._touchStartY = e.touches[0].clientY
        const sheet = this.el.querySelector("[data-sheet]") || this.el.firstElementChild
        this._sheetHeight = sheet ? sheet.offsetHeight : 300
        this._currentTranslateY = 0
        if (sheet) sheet.style.transition = "none"
      }

      this._onTouchMove = (e) => {
        const delta = e.touches[0].clientY - this._touchStartY
        if (delta < 0) return // Don't drag upward beyond origin
        this._currentTranslateY = delta
        const sheet = this.el.querySelector("[data-sheet]") || this.el.firstElementChild
        if (sheet) {
          sheet.style.transform = `translateY(${delta}px)`
        }
      }

      this._onTouchEnd = () => {
        const sheet = this.el.querySelector("[data-sheet]") || this.el.firstElementChild
        if (sheet) sheet.style.transition = ""

        if (this._currentTranslateY > this._sheetHeight * 0.3) {
          this._close()
        } else {
          // Snap back
          const sheet = this.el.querySelector("[data-sheet]") || this.el.firstElementChild
          if (sheet) {
            sheet.style.transform = ""
          }
        }
        this._currentTranslateY = 0
      }

      handle.addEventListener("touchstart", this._onTouchStart, { passive: true })
      handle.addEventListener("touchmove", this._onTouchMove, { passive: true })
      handle.addEventListener("touchend", this._onTouchEnd)
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this._onBackdropClick)

    const closeBtn = this.el.querySelector("[data-close-sheet]")
    if (closeBtn && this._onCloseClick) {
      closeBtn.removeEventListener("click", this._onCloseClick)
    }

    const handle = this.el.querySelector("[data-drag-handle]")
    if (handle) {
      if (this._onTouchStart) handle.removeEventListener("touchstart", this._onTouchStart)
      if (this._onTouchMove) handle.removeEventListener("touchmove", this._onTouchMove)
      if (this._onTouchEnd) handle.removeEventListener("touchend", this._onTouchEnd)
    }
  },

  _open() {
    this.el.classList.remove("translate-y-full")
    this.el.classList.add("translate-y-0")
    const sheet = this.el.querySelector("[data-sheet]") || this.el.firstElementChild
    if (sheet) {
      sheet.style.transform = ""
    }
  },

  _close() {
    this.el.classList.remove("translate-y-0")
    this.el.classList.add("translate-y-full")
  },
}

export default BoardSheet
