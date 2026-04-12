<script setup lang="ts">
import { ref } from 'vue'

const visible = ref(false)
const pickedNumber = ref(0)
const isOnTicket = ref(false)
let dismissTimer: ReturnType<typeof setTimeout> | null = null

function getPreferredVoice(): SpeechSynthesisVoice | null {
  const voices = window.speechSynthesis.getVoices()
  // Prefer warm/soft English voices by platform name
  for (const name of ['Samantha', 'Karen', 'Moira', 'Tessa', 'Zira', 'Google UK English Female']) {
    const v = voices.find(v => v.name.includes(name))
    if (v) return v
  }
  return voices.find(v => v.lang.startsWith('en')) ?? null
}

function speak(number: number) {
  if (!window.speechSynthesis) return
  window.speechSynthesis.cancel()
  const utterance = new SpeechSynthesisUtterance(String(number))
  utterance.rate = 0.78
  utterance.pitch = 0.88
  utterance.volume = 0.9
  const voice = getPreferredVoice()
  if (voice) utterance.voice = voice
  window.speechSynthesis.speak(utterance)
}

function show(number: number, onTicket: boolean, durationMs: number) {
  if (dismissTimer) clearTimeout(dismissTimer)
  pickedNumber.value = number
  isOnTicket.value = onTicket
  visible.value = true
  speak(number)
  dismissTimer = setTimeout(() => { visible.value = false }, durationMs)
}

function dismiss() {
  visible.value = false
  if (dismissTimer) {
    clearTimeout(dismissTimer)
    dismissTimer = null
  }
}

defineExpose({ show })
</script>

<template>
  <Transition name="number-call">
    <div
      v-if="visible"
      class="fixed inset-0 z-50 flex items-center justify-center pointer-events-none"
    >
      <div
        @click="dismiss"
        class="pointer-events-auto flex flex-col items-center gap-3 bg-[--surface]/95 backdrop-blur-xl rounded-3xl border border-[--border] shadow-2xl px-12 py-10 text-center cursor-pointer select-none"
      >
        <div class="text-xs font-bold text-[--text-secondary] uppercase tracking-widest">Number Called</div>

        <div class="w-32 h-32 bg-gradient-to-br from-indigo-500 to-purple-600 rounded-full flex items-center justify-center shadow-[0_0_60px_rgba(99,102,241,0.5)] text-white font-black text-6xl">
          {{ pickedNumber }}
        </div>

        <div
          v-if="isOnTicket"
          class="flex items-center gap-2 px-4 py-2 bg-green-500/15 border border-green-500/30 rounded-full text-green-500 font-bold text-sm"
        >
          <span>✓</span> On your ticket!
        </div>

        <p class="text-xs text-[--text-muted] mt-1">Tap to dismiss</p>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.number-call-enter-active {
  animation: number-call-in 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.number-call-leave-active {
  animation: number-call-out 0.25s ease-in forwards;
}

@keyframes number-call-in {
  from { opacity: 0; transform: scale(0.8); }
  to { opacity: 1; transform: scale(1); }
}
@keyframes number-call-out {
  from { opacity: 1; transform: scale(1); }
  to { opacity: 0; transform: scale(0.9); }
}
</style>
