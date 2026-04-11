<script setup lang="ts">
defineProps<{ variant?: 'live' | 'paused' | 'finished' | 'lobby' }>()
const map = { live: 'bg-green-500/20 text-green-400', paused: 'bg-yellow-500/20 text-yellow-400', finished: 'bg-zinc-500/20 text-zinc-400', lobby: 'bg-blue-500/20 text-blue-400' }
</script>
<template>
  <span :class="['inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium', map[variant ?? 'lobby']]"><slot /></span>
</template>
