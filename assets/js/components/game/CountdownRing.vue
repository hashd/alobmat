<script setup lang="ts">
import { computed } from 'vue'
const props = defineProps<{ secondsLeft: number; totalSeconds: number }>()
const pct = computed(() => Math.max(0, Math.min(1, props.secondsLeft / props.totalSeconds)))
const dash = computed(() => {
  const c = 2 * Math.PI * 28
  return `${c * pct.value} ${c}`
})
</script>
<template>
  <div class="relative flex h-20 w-20 items-center justify-center">
    <svg class="absolute -rotate-90" width="80" height="80">
      <circle cx="40" cy="40" r="28" fill="none" stroke="var(--border)" stroke-width="4" />
      <circle cx="40" cy="40" r="28" fill="none" stroke="var(--accent)" stroke-width="4"
        :stroke-dasharray="dash" stroke-linecap="round" class="transition-all duration-200" />
    </svg>
    <span class="text-xl font-bold tabular-nums">{{ secondsLeft }}</span>
  </div>
</template>
