export function useConfetti() {
  function fire() {
    import('canvas-confetti').then(({ default: confetti }) => {
      confetti({ particleCount: 120, spread: 70, origin: { y: 0.6 } })
    }).catch(() => {})
  }
  return { fire }
}
