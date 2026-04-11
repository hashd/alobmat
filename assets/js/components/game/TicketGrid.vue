<script setup lang="ts">
import { ref } from 'vue'
import type { Ticket } from '@/types/domain'

const props = defineProps<{
  ticket: Ticket
  struck: Set<number>
  pickedNumbers: number[]
  interactive?: boolean
}>()
const emit = defineEmits<{ strike: [number: number] }>()

const inFlight = ref<Set<number>>(new Set())
const rejected = ref<Set<number>>(new Set())

function handleClick(n: number | null) {
  if (!n || !props.interactive) return
  if (props.struck.has(n) || inFlight.value.has(n)) return
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
  <div class="grid gap-1 rounded-xl border border-[--border] bg-[--surface] p-3">
    <div v-for="(row, ri) in ticket.rows" :key="ri" class="grid grid-cols-9 gap-1">
      <div
        v-for="(cell, ci) in row"
        :key="ci"
        :data-number="cell ?? undefined"
        @click="handleClick(cell)"
        :class="[
          'flex h-9 w-full items-center justify-center rounded-lg text-sm font-semibold transition-all select-none',
          !cell ? 'bg-transparent' :
          rejected.has(cell) ? 'animate-shake bg-red-500/20 text-red-400' :
          struck.has(cell) ? 'bg-[--accent]/20 text-[--accent] line-through' :
          pickedNumbers.includes(cell) ? 'bg-[--accent] text-white cursor-pointer' :
          interactive ? 'cursor-pointer bg-[--bg] text-[--text-primary] hover:bg-[--surface-2]' :
          'bg-[--bg] text-[--text-primary]'
        ]"
      >
        {{ cell ?? '' }}
      </div>
    </div>
  </div>
</template>
