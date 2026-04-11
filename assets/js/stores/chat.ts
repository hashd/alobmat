import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { ChatEntry } from '@/types/domain'
import type { ChatEvent, NumberPickedEvent, PrizeClaimedEvent, BogeyEvent } from '@/types/channel'

const MAX_ENTRIES = 50

export const useChatStore = defineStore('chat', () => {
  const entries = ref<ChatEntry[]>([])
  const filter = ref<'all' | 'chat' | 'events'>('all')

  function addEntry(entry: ChatEntry) {
    entries.value = [...entries.value.slice(-(MAX_ENTRIES - 1)), entry]
  }

  function onChat(event: ChatEvent) {
    addEntry({ id: event.id, type: 'chat', user_id: event.user_id, user_name: event.user_name, text: event.text, timestamp: event.timestamp })
  }

  function onPick(event: NumberPickedEvent) {
    addEntry({ id: `pick-${event.number}`, type: 'pick', number: event.number, timestamp: new Date().toISOString() })
  }

  function onPrizeClaimed(event: PrizeClaimedEvent) {
    addEntry({ id: `prize-${event.prize}`, type: 'prize_claimed', user_name: event.winner_name, prize: event.prize, timestamp: new Date().toISOString() })
  }

  function onBogey(event: BogeyEvent) {
    addEntry({ id: `bogey-${Date.now()}`, type: 'bogey', user_id: event.user_id, timestamp: new Date().toISOString() })
  }

  function reset() { entries.value = [] }

  return { entries, filter, onChat, onPick, onPrizeClaimed, onBogey, reset }
})
