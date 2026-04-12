<script setup lang="ts">
import { ref, computed } from 'vue'
import type { Ticket } from '@/types/domain'

const props = defineProps<{
  ticket: Ticket
  struck: Set<number>
  pickedNumbers: number[]
  interactive?: boolean
}>()
const emit = defineEmits<{ strike: [number: number] }>()

const pickedSet = computed(() => new Set(props.pickedNumbers))
const inFlight = ref<Set<number>>(new Set())
const rejected = ref<Set<number>>(new Set())
const macroRejectNode = ref<number | null>(null)

function handleClick(n: number | null) {
  if (!n || !props.interactive) return
  if (props.struck.has(n) || inFlight.value.has(n)) return

  if (!pickedSet.value.has(n)) {
    // Macro rejection!
    macroRejectNode.value = n
    setTimeout(() => {
      if (macroRejectNode.value === n) macroRejectNode.value = null
    }, 1000)
    return
  }

  inFlight.value = new Set([...inFlight.value, n])
  emit('strike', n)
}

function onStrikeResult(n: number, result: 'ok' | 'rejected') {
  inFlight.value = new Set([...inFlight.value].filter(x => x !== n))
  if (result === 'rejected') {
    rejected.value = new Set([...rejected.value, n])
    setTimeout(() => {
      rejected.value = new Set([...rejected.value].filter(x => x !== n))
    }, 600)
  }
}

defineExpose({ onStrikeResult })
</script>

<template>
  <div class="grid gap-1.5 md:gap-2 rounded-2xl bg-white/5 dark:bg-black/20 p-2 md:p-3 relative overflow-visible">
    <div class="absolute inset-0 border border-white/20 rounded-2xl pointer-events-none"></div>

    <!-- Macro Rejection Overlay Layer -->
    <div v-if="macroRejectNode" class="pointer-events-none absolute inset-0 z-50 flex items-center justify-center overflow-visible">
      <div class="absolute inset-0 bg-red-500/10 rounded-2xl mix-blend-overlay animate-[flash_0.4s_ease-out_forwards]"></div>
      <!-- Huge X -> scale down and explode -->
      <svg class="text-red-500/90 drop-shadow-[0_0_30px_rgba(239,68,68,0.8)] w-full h-full p-10 animate-[slam-explode_0.6s_cubic-bezier(0.175,0.885,0.32,1.275)_forwards]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M6 18L18 6M6 6l12 12"></path>
      </svg>
    </div>

    <div v-for="(row, ri) in ticket.rows" :key="ri" class="grid grid-cols-9 gap-1.5 md:gap-2 relative z-10">
      <div
        v-for="(cell, ci) in row"
        :key="ci"
        :data-number="cell ?? undefined"
        @click="handleClick(cell)"
        :class="[
          'relative flex h-10 md:h-12 w-full items-center justify-center rounded-xl text-base md:text-lg font-black transition-all duration-300 select-none shadow-sm',
          !cell ? 'bg-transparent shadow-none border border-dashed border-[--border]/30' :
          macroRejectNode === cell ? 'animate-[violent-shake_0.4s_ease-in-out_infinite] bg-red-600 !text-white border-2 border-red-500 shadow-[0_0_25px_rgba(239,68,68,0.8)] z-20 scale-110' :
          rejected.has(cell) ? 'animate-shake bg-red-500/20 text-red-500 border border-red-500/50 shadow-[0_0_15px_rgba(239,68,68,0.3)]' :
          struck.has(cell) ? 'bg-indigo-500/20 text-indigo-500 shadow-inner border border-indigo-500/20 scale-95 opacity-60' :
          pickedSet.has(cell) ? 'bg-gradient-to-br from-indigo-500 to-purple-600 text-white cursor-pointer hover:shadow-[0_0_20px_rgba(99,102,241,0.5)] border border-indigo-400/50 scale-105 z-10 animate-bounce-in' :
          interactive ? 'cursor-pointer bg-[--surface] text-[--text-primary] border border-[--border] hover:-translate-y-1 hover:shadow-md hover:border-indigo-500/50' :
          'bg-[--surface]/80 text-[--text-secondary] border border-[--border]'
        ]"
      >
        <span class="relative z-10">{{ cell ?? '' }}</span>
        
        <!-- Struck indicator cross -->
        <div v-if="struck.has(cell)" class="absolute inset-0 flex items-center justify-center pointer-events-none opacity-80">
           <svg class="w-full h-full text-indigo-500 p-1 drop-shadow-sm" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M6 18L18 6M6 6l12 12"></path></svg>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes flash {
  0% { opacity: 0; }
  10% { opacity: 1; }
  100% { opacity: 0; }
}

@keyframes slam-explode {
  0% { transform: scale(3); opacity: 0; filter: blur(10px); }
  30% { transform: scale(0.9); opacity: 1; filter: blur(0); }
  50% { transform: scale(1.05); }
  70% { transform: scale(1); opacity: 1; }
  100% { transform: scale(1.5); opacity: 0; filter: blur(5px); }
}

@keyframes violent-shake {
  0% { transform: translate(0, 0) rotate(0deg) scale(1.1); }
  20% { transform: translate(-3px, 2px) rotate(-3deg) scale(1.1); }
  40% { transform: translate(3px, -2px) rotate(3deg) scale(1.1); }
  60% { transform: translate(-3px, -2px) rotate(-3deg) scale(1.1); }
  80% { transform: translate(3px, 2px) rotate(3deg) scale(1.1); }
  100% { transform: translate(0, 0) rotate(0deg) scale(1.1); }
}
</style>
