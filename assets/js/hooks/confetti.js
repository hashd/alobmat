const Confetti = {
  mounted() {
    this._confettiModule = null

    // Pre-load canvas-confetti
    import("canvas-confetti")
      .then((mod) => {
        this._confettiModule = mod.default || mod
      })
      .catch(() => {
        // canvas-confetti not installed; confetti will be a no-op
      })

    this.handleEvent("confetti", (payload) => {
      this._fire(payload)
    })
  },

  _fire(payload) {
    const fire = (confetti) => {
      const defaults = {
        particleCount: 100,
        spread: 70,
        origin: { y: 0.6 },
        ...payload,
      }

      confetti(defaults)

      // Extended burst
      setTimeout(() => confetti({ ...defaults, particleCount: 50 }), 500)
      setTimeout(() => confetti({ ...defaults, particleCount: 30, spread: 100 }), 1000)
    }

    if (this._confettiModule) {
      fire(this._confettiModule)
    } else {
      // Try loading again
      import("canvas-confetti")
        .then((mod) => {
          this._confettiModule = mod.default || mod
          fire(this._confettiModule)
        })
        .catch(() => {
          // Silently fail - confetti is non-essential
        })
    }
  },
}

export default Confetti
