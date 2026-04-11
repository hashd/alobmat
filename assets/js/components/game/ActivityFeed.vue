<script setup lang="ts">
import { computed, ref } from 'vue'
import { useAutoScroll } from '@/composables/useAutoScroll'
import { useChatStore } from '@/stores/chat'
import type { ChatEntry } from '@/types/domain'

const chat = useChatStore()
const emit = defineEmits<{ sendChat: [text: string] }>()

const filtered = computed<ChatEntry[]>(() =>
  chat.filter === 'all' ? chat.entries :
  chat.filter === 'chat' ? chat.entries.filter(e => e.type === 'chat') :
  chat.entries.filter(e => e.type !== 'chat')
)

const { containerRef } = useAutoScroll(() => filtered.value.length)
const draft = ref('')

const filterOptions = [
  { value: 'all', label: 'All' },
  { value: 'chat', label: 'Chat' },
  { value: 'events', label: 'Events' },
]
</script>
<template>
  <div class="flex flex-col h-full">
    <div class="flex gap-2 mb-2">
      <button v-for="opt in filterOptions" :key="opt.value"
        @click="chat.filter = opt.value as any"
        :class="['text-xs px-2 py-1 rounded', chat.filter === opt.value ? 'bg-[--accent] text-white' : 'text-[--text-secondary]']"
      >{{ opt.label }}</button>
    </div>
    <div ref="containerRef" class="flex-1 overflow-y-auto space-y-1 min-h-0">
      <div v-for="entry in filtered" :key="entry.id" class="text-sm px-1">
        <span v-if="entry.type === 'chat'" class="text-[--text-primary]">
          <span class="font-semibold text-[--accent]">{{ entry.user_name }}:</span> {{ entry.text }}
        </span>
        <span v-else-if="entry.type === 'pick'" class="text-[--text-secondary]">Number {{ entry.number }} picked</span>
        <span v-else-if="entry.type === 'prize_claimed'" class="text-yellow-400">🏆 {{ entry.user_name }} won {{ entry.prize }}!</span>
        <span v-else-if="entry.type === 'bogey'" class="text-red-400">❌ Bogey!</span>
        <span v-else class="text-[--text-secondary] italic">{{ entry.text }}</span>
      </div>
    </div>
    <form @submit.prevent="emit('sendChat', draft.value); draft.value = ''" class="mt-2 flex gap-2">
      <input v-model="draft" placeholder="Say something…" class="flex-1 rounded-lg border border-[--border] bg-[--bg] px-3 py-2 text-sm focus:outline-none focus:border-[--accent]" />
      <button type="submit" class="rounded-lg bg-[--accent] px-3 py-2 text-sm text-white">Send</button>
    </form>
  </div>
</template>
