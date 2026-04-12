<script setup lang="ts">
import { computed } from 'vue'
const props = defineProps<{ secondsLeft: number; totalSeconds: number }>()
const pct = computed(() => Math.max(0, Math.min(1, props.secondsLeft / props.totalSeconds)))
const dash = computed(() => {
  const c = 2 * Math.PI * 28
  return `${c * pct.value} ${c}`
})
const urgencyClass = computed(() => props.secondsLeft <= 3 ? 'text-red-500 stroke-red-500' : 'text-indigo-500 stroke-indigo-500')
</script>
<template>
  <div class="relative flex h-24 w-24 items-center justify-center bg-[--bg]/50 rounded-full shadow-[inset_0_4px_10px_rgb(0,0,0,0.05)] border border-[--border]">
    <svg class="absolute -rotate-90 w-full h-full" width="96" height="96" viewBox="0 0 80 80">
      <circle cx="40" cy="40" r="28" fill="none" stroke="var(--border)" stroke-width="6" class="opacity-30" />
      <circle cx="40" cy="40" r="28" fill="none" :stroke-dasharray="dash" stroke-linecap="round" stroke-width="6"
        class="transition-all duration-1000 ease-linear shadow-sm" :class="[urgencyClass]" />
    </svg>
    <div class="flex flex-col items-center justify-center relative z-10 transition-all duration-300" :class="[urgencyClass, props.secondsLeft <= 3 ? 'scale-110 animate-pulse' : '']">
      <span class="text-3xl font-black tabular-nums leading-none mb-0.5">{{ secondsLeft }}</span>
    </div>
  </div>
</template>
