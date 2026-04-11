const TicketStrike = {
  mounted() {
    this._inFlight = new Set()

    this._onClick = (e) => {
      const number = parseInt(this.el.dataset.number, 10)
      if (isNaN(number)) return
      if (this._inFlight.has(number)) return

      this.el.classList.add("striking")
      this._inFlight.add(number)

      this.pushEvent("strike_out", { number })
    }

    this.el.addEventListener("click", this._onClick)

    this._onPick = (e) => {
      const picked = e.detail && e.detail.number
      if (!picked) return

      const number = parseInt(this.el.dataset.number, 10)
      if (picked !== number) return
      if (this._inFlight.has(number)) return
      if (this.el.dataset.struck === "true") return

      this.el.classList.add("striking")
      this._inFlight.add(number)
      this.pushEvent("strike_out", { number })
    }

    window.addEventListener("phx:pick", this._onPick)
  },

  updated() {
    const result = this.el.dataset.strikeResult
    const number = parseInt(this.el.dataset.number, 10)

    if (result === "rejected") {
      this.el.classList.remove("striking")
      this.el.classList.add("animate-shake")
      this._inFlight.delete(number)

      setTimeout(() => {
        this.el.classList.remove("animate-shake")
      }, 600)
    } else if (result === "confirmed") {
      this.el.classList.remove("striking")
      this._inFlight.delete(number)
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    window.removeEventListener("phx:pick", this._onPick)
  },
}

export default TicketStrike
