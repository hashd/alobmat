import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { PresenceDiff, PresenceMeta } from '@/types/channel'

export const usePresenceStore = defineStore('presence', () => {
  const players = ref<Map<string, PresenceMeta>>(new Map())

  function syncPresence(diff: PresenceDiff) {
    for (const [userId, meta] of Object.entries(diff.joins)) {
      players.value.set(userId, meta)
    }
    for (const userId of Object.keys(diff.leaves)) {
      players.value.delete(userId)
    }
  }

  function reset() {
    players.value = new Map()
  }

  return { players, syncPresence, reset }
})
