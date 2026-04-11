<script setup lang="ts">
defineProps<{ picks: number[] }>()
const allNumbers = Array.from({ length: 90 }, (_, i) => i + 1)
</script>
<template>
  <div class="grid grid-cols-10 gap-1">
    <div
      v-for="n in allNumbers"
      :key="n"
      :class="[
        'flex h-8 w-full items-center justify-center rounded text-xs font-medium transition-all',
        picks.includes(n) ? 'bg-[--accent] text-white' : 'bg-[--surface] text-[--text-secondary]'
      ]"
    >{{ n }}</div>
  </div>
</template>
