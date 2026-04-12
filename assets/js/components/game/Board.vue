<script setup lang="ts">
import { computed } from 'vue'
const props = defineProps<{ picks: number[] }>()
const pickSet = computed(() => new Set(props.picks))
const allNumbers = Array.from({ length: 90 }, (_, i) => i + 1)
</script>
<template>
  <div class="grid grid-cols-10 gap-1 md:gap-1.5 max-w-lg mx-auto">
    <div
      v-for="n in allNumbers"
      :key="n"
      :class="[
        'flex aspect-square w-full max-w-[48px] max-h-[48px] mx-auto items-center justify-center rounded-full text-[10px] sm:text-xs md:text-sm font-bold transition-all duration-500 select-none border',
        pickSet.has(n) ? 'bg-gradient-to-br from-indigo-500 to-purple-600 text-white border-transparent shadow-[0_0_15px_rgba(99,102,241,0.4)] scale-110 z-10' : 'bg-[--surface] text-[--text-muted] border-[--border]'
      ]"
    >{{ n }}</div>
  </div>
</template>
