import { ref, watchEffect } from 'vue'

export function useAutoScroll(deps: () => unknown) {
  const containerRef = ref<HTMLElement | null>(null)

  watchEffect(() => {
    deps()
    if (containerRef.value) {
      containerRef.value.scrollTop = containerRef.value.scrollHeight
    }
  })

  return { containerRef }
}
