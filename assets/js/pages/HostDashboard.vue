<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useChannel } from '@/composables/useChannel'
import { api } from '@/api/client'
import Board from '@/components/game/Board.vue'
import ConnectionStatus from '@/components/ui/ConnectionStatus.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import Avatar from '@/components/ui/Avatar.vue'
import Card from '@/components/ui/Card.vue'

const route = useRoute()
const router = useRouter()
const code = route.params.code as string

const { gameStore } = useChannel(code)
const loading = ref<string | null>(null)
const actionError = ref<string | null>(null)

async function action(fn: () => Promise<unknown>, key: string) {
  loading.value = key
  actionError.value = null
  try { await fn() } catch (e: any) { actionError.value = e.message ?? 'Action failed' }
  finally { loading.value = null }
}

async function playAgain() {
  const { code: newCode } = await api.games.clone(code)
  router.push(`/game/${newCode}/host`)
}
</script>
<template>
  <div class="flex flex-col min-h-screen bg-[--bg] text-[--text-primary] p-4">
    <!-- Header -->
    <div class="flex items-center gap-3 mb-6">
      <Button variant="ghost" @click="router.push('/')">←</Button>
      <div>
        <div class="flex items-center gap-2">
          <span class="font-bold text-lg">{{ gameStore.name || code }}</span>
          <Badge :variant="gameStore.status as any">{{ gameStore.status }}</Badge>
        </div>
        <p class="font-mono text-sm text-[--text-secondary]">Code: {{ code }}</p>
      </div>
    </div>

    <!-- LOBBY -->
    <div v-if="gameStore.status === 'lobby'" class="flex flex-col gap-4">
      <Card>
        <h2 class="mb-3 font-semibold">Players ({{ gameStore.players.length }})</h2>
        <div class="flex flex-wrap gap-2">
          <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-2 rounded-full border border-[--border] px-3 py-1.5 text-sm">
            <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
            {{ p.name }}
          </div>
          <p v-if="!gameStore.players.length" class="text-[--text-secondary] text-sm">Waiting for players…</p>
        </div>
      </Card>
      <Button :loading="loading === 'start'" @click="action(() => api.games.start(code), 'start')" :disabled="gameStore.players.length === 0">
        Start game
      </Button>
    </div>

    <!-- RUNNING / PAUSED -->
    <div v-else-if="['running','paused'].includes(gameStore.status)" class="flex flex-col gap-4">
      <div class="flex gap-2 flex-wrap">
        <Button v-if="gameStore.status === 'running'" variant="secondary" :loading="loading === 'pause'" @click="action(() => api.games.pause(code), 'pause')">Pause</Button>
        <Button v-if="gameStore.status === 'paused'" :loading="loading === 'resume'" @click="action(() => api.games.resume(code), 'resume')">Resume</Button>
        <Button variant="danger" :loading="loading === 'end'" @click="action(() => api.games.end(code), 'end')">End game</Button>
      </div>

      <Card>
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-semibold">Board</h2>
          <span class="text-sm text-[--text-secondary]">{{ gameStore.board.count }} / 90</span>
        </div>
        <Board :picks="gameStore.board.picks" />
      </Card>

      <Card>
        <h2 class="mb-3 font-semibold">Players</h2>
        <div class="flex flex-col gap-2">
          <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-3 text-sm">
            <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
            <span class="flex-1">{{ p.name }}</span>
            <span v-if="p.prizes_won.length" class="text-yellow-400 text-xs">{{ p.prizes_won.join(', ') }}</span>
            <span v-if="p.bogeys" class="text-red-400 text-xs">{{ p.bogeys }}× bogey</span>
          </div>
        </div>
      </Card>

      <Card>
        <h2 class="mb-3 font-semibold">Prizes</h2>
        <div class="flex flex-col gap-2">
          <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex justify-between text-sm">
            <span>{{ prize.replace(/_/g, ' ') }}</span>
            <span :class="status.claimed ? 'text-yellow-400' : 'text-[--text-secondary]'">
              {{ status.claimed ? (gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? '?') : 'Unclaimed' }}
            </span>
          </div>
        </div>
      </Card>
    </div>

    <!-- FINISHED -->
    <div v-else-if="gameStore.status === 'finished'" class="flex flex-col gap-4">
      <h2 class="text-xl font-bold">Game over!</h2>
      <Card>
        <h3 class="mb-3 font-semibold">Final results</h3>
        <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex justify-between text-sm border-b border-[--border] py-2">
          <span>{{ prize.replace(/_/g, ' ') }}</span>
          <span>{{ status.claimed ? (gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? '?') : '—' }}</span>
        </div>
      </Card>
      <div class="flex gap-2">
        <Button :loading="loading === 'clone'" @click="action(playAgain, 'clone')">Play again</Button>
        <Button variant="secondary" @click="router.push('/')">Home</Button>
      </div>
    </div>

    <p v-if="actionError" class="mt-4 text-sm text-red-500">{{ actionError }}</p>
    <ConnectionStatus :connected="gameStore.channelConnected" />
  </div>
</template>
