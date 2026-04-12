<script setup lang="ts">
defineProps<{ variant?: 'live' | 'running' | 'paused' | 'finished' | 'lobby' }>()
const map: Record<string, string> = { 
  live: 'bg-green-500/10 text-green-500 border-green-500/30 shadow-[0_0_10px_rgba(34,197,94,0.2)]', 
  running: 'bg-green-500/10 text-green-500 border-green-500/30 shadow-[0_0_10px_rgba(34,197,94,0.2)]', 
  paused: 'bg-yellow-500/10 text-yellow-500 border-yellow-500/30 shadow-[0_0_10px_rgba(234,179,8,0.2)]', 
  finished: 'bg-zinc-500/10 text-zinc-400 border-zinc-500/30', 
  lobby: 'bg-indigo-500/10 text-indigo-500 border-indigo-500/30 shadow-[0_0_10px_rgba(99,102,241,0.2)]'
}
</script>
<template>
  <span :class="['inline-flex items-center rounded-full px-2.5 py-0.5 text-[10px] uppercase tracking-wider font-extrabold border backdrop-blur-sm', map[variant ?? 'lobby']]">
    <slot />
  </span>
</template>
