<script setup lang="ts">
import { ref } from 'vue'

const floaters = ref<Array<{ id: number; emoji: string; x: number }>>([])
let counter = 0

function addReaction(emoji: string) {
  const id = counter++
  floaters.value.push({ id, emoji, x: 20 + Math.random() * 60 })
  setTimeout(() => { floaters.value = floaters.value.filter(f => f.id !== id) }, 2000)
}

defineExpose({ addReaction })
</script>
<template>
  <div class="pointer-events-none fixed inset-0 z-40 overflow-hidden">
    <TransitionGroup name="float">
      <div
        v-for="f in floaters"
        :key="f.id"
        class="absolute bottom-16 text-2xl"
        :style="{ left: `${f.x}%` }"
      >{{ f.emoji }}</div>
    </TransitionGroup>
  </div>
</template>
<style scoped>
.float-enter-from { opacity: 1; transform: translateY(0); }
.float-leave-to { opacity: 0; transform: translateY(-120px); }
.float-enter-active, .float-leave-active { transition: all 2s ease-out; }
</style>
