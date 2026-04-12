import { ref, onUnmounted } from 'vue'

export function useCountdown(targetIso: () => string | null) {
  const secondsLeft = ref(0)
  let timer: ReturnType<typeof setInterval> | null = null

  function start() {
    if (timer) clearInterval(timer)
    timer = setInterval(() => {
      const target = targetIso()
      if (!target) { secondsLeft.value = 0; return }
      const diff = Math.max(0, Math.ceil((new Date(target).getTime() - Date.now()) / 1000))
      secondsLeft.value = diff
    }, 200)
  }

  function stop() {
    if (timer) clearInterval(timer)
  }

  onUnmounted(stop)

  return { secondsLeft, start, stop }
}
