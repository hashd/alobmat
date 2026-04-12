<script setup lang="ts">
import { ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useChannel } from '@/composables/useChannel'
import { useAuthStore } from '@/stores/auth'
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
const auth = useAuthStore()

// Redirect non-host users once game state is hydrated
watch(() => gameStore.code, (c) => {
  if (c && gameStore.hostId && gameStore.hostId !== auth.user?.id) {
    router.replace(`/game/${c}`)
  }
})
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

async function setTicketCount(userId: string, count: number) {
  try { await api.games.setTicketCount(code, userId, count) } catch (_) { /* best-effort */ }
}
</script>
<template>
  <div class="flex flex-col min-h-screen bg-[--bg] text-[--text-primary] relative overflow-hidden">
    <!-- Decorative Ambient Glows -->
    <div class="fixed top-0 inset-x-0 h-96 bg-gradient-to-b from-indigo-500/10 to-transparent pointer-events-none"></div>
    <div v-if="gameStore.status === 'running'" class="fixed inset-0 bg-green-500/5 pointer-events-none animate-pulse"></div>

    <!-- Header -->
    <header class="relative z-10 flex items-center justify-between px-6 py-5 border-b border-[--border] bg-[--bg]/80 backdrop-blur-xl">
      <div class="flex items-center gap-4">
        <Button variant="ghost" @click="router.push('/')" class="!px-3 !py-1 flex items-center gap-1 rounded-full"><span class="text-lg leading-none">←</span></Button>
        <div>
          <div class="flex items-center gap-3">
            <h1 class="font-bold text-2xl tracking-tight bg-gradient-to-br from-white to-gray-400 bg-clip-text text-transparent drop-shadow-sm">{{ gameStore.name || 'Game Lobby' }}</h1>
            <Badge :variant="gameStore.status as any" class="text-xs px-2.5 py-0.5 rounded-full uppercase tracking-wider font-bold shadow-sm">{{ gameStore.status }}</Badge>
          </div>
          <div class="flex items-center gap-2 text-sm text-[--text-secondary] mt-1">
            <span class="font-mono bg-[--surface] px-2 py-0.5 rounded-md border border-[--border]">Code: <span class="text-indigo-400 font-bold tracking-widest">{{ code }}</span></span>
          </div>
        </div>
      </div>
      <div>
        <ConnectionStatus :connected="gameStore.channelConnected" />
      </div>
    </header>

    <main class="relative z-10 flex-1 p-6 md:p-8 max-w-7xl w-full mx-auto animate-fade-in-up">
      <!-- LOBBY -->
      <div v-if="gameStore.status === 'lobby'" class="flex flex-col items-center justify-center py-12">
        <div class="text-center mb-8 max-w-xl">
          <div class="w-24 h-24 bg-indigo-500/10 rounded-full flex items-center justify-center mx-auto mb-6 shadow-[0_0_50px_rgba(99,102,241,0.2)]">
            <span class="text-4xl">👋</span>
          </div>
          <h2 class="text-3xl font-bold mb-3">Waiting for players</h2>
          <p class="text-[--text-secondary] text-lg">Share the game code <span class="font-mono text-indigo-400 font-bold px-2">{{ code }}</span> with your players so they can join.</p>
        </div>

        <Card class="w-full max-w-3xl mb-8 p-6">
          <div class="flex items-center justify-between mb-6 border-b border-[--border] pb-4">
            <h3 class="font-bold text-xl flex items-center gap-2"><span class="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span> Players Joined <span class="text-sm px-2 py-0.5 bg-[--elevated] rounded-full text-[--text-secondary]">{{ gameStore.players.length }}</span></h3>
          </div>
          <div class="flex flex-col gap-2 min-h-[100px]">
            <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-3 p-3 rounded-xl bg-[--bg] border border-[--border] animate-scale-in">
              <Avatar :name="p.name" :user-id="p.user_id" size="sm" class="ring-2 ring-indigo-500/30" />
              <span class="flex-1 font-medium text-sm">{{ p.name }}</span>
              <div class="flex items-center gap-1">
                <span class="text-xs text-[--text-secondary] mr-1">Tickets:</span>
                <button v-for="n in 6" :key="n" type="button"
                  @click="setTicketCount(p.user_id, n)"
                  :class="['w-7 h-7 rounded-lg text-xs font-bold transition-all',
                    (p.ticket_count ?? gameStore.settings.default_ticket_count) === n
                      ? 'bg-indigo-500 text-white shadow-sm'
                      : 'bg-[--surface] text-[--text-secondary] border border-[--border] hover:border-indigo-500/50']"
                >{{ n }}</button>
              </div>
            </div>
            <p v-if="!gameStore.players.length" class="text-[--text-secondary] text-sm animate-pulse text-center py-8">No players have joined yet...</p>
          </div>
        </Card>

        <Button size="lg" class="px-12 py-4 text-lg rounded-full shadow-[0_0_30px_rgba(99,102,241,0.4)]" :loading="loading === 'start'" @click="action(() => api.games.start(code), 'start')" :disabled="gameStore.players.length === 0">
          Start Game Now
        </Button>
      </div>

      <!-- RUNNING / PAUSED -->
      <div v-else-if="['running','paused'].includes(gameStore.status)" class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        
        <!-- Main Board Area -->
        <div class="lg:col-span-8 flex flex-col gap-6">
          <Card class="p-6 border-t-4 border-t-indigo-500">
            <div class="flex items-center justify-between mb-6">
              <h2 class="font-bold text-xl">The Board</h2>
              <div class="flex items-center gap-4">
                <div class="flex items-center gap-2 bg-[--surface] px-4 py-1.5 rounded-full border border-[--border]">
                  <span class="text-xs text-[--text-secondary] uppercase tracking-wider font-bold">Progress</span>
                  <span class="font-mono font-bold text-indigo-400">{{ gameStore.board.count }} <span class="text-[--text-muted]">/ 90</span></span>
                </div>
              </div>
            </div>
            
            <div class="bg-[--bg] rounded-xl p-4 border border-[--border] overflow-hidden">
              <Board :picks="gameStore.board.picks" />
            </div>
          </Card>
          
          <div class="flex justify-center gap-4 py-4">
            <Button v-if="gameStore.status === 'running'" variant="secondary" class="px-8" :loading="loading === 'pause'" @click="action(() => api.games.pause(code), 'pause')">Pause Game</Button>
            <Button v-if="gameStore.status === 'paused'" class="px-8" :loading="loading === 'resume'" @click="action(() => api.games.resume(code), 'resume')">Resume Game</Button>
            <Button variant="danger" variant-type="outline" class="px-8" :loading="loading === 'end'" @click="action(() => api.games.end(code), 'end')">End Game</Button>
          </div>
        </div>

        <!-- Sidebar Area -->
        <div class="lg:col-span-4 flex flex-col gap-6">
          <Card class="!p-0 overflow-hidden border border-yellow-500/20 shadow-[0_4px_20px_rgba(251,191,36,0.1)]">
            <div class="bg-gradient-to-r from-yellow-500/10 to-amber-500/10 border-b border-yellow-500/20 p-4">
              <h2 class="font-bold flex items-center gap-2 text-yellow-500"><span class="text-lg">🏆</span> Prize Status</h2>
            </div>
            <div class="p-4 flex flex-col gap-3">
              <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex items-center justify-between text-sm p-3 rounded-lg bg-[--surface] border border-[--border]">
                <span class="font-medium capitalize text-[--text-primary]">{{ prize.replace(/_/g, ' ') }}</span>
                <span class="px-3 py-1 rounded-full text-xs font-bold" :class="status.claimed ? 'bg-yellow-500/20 text-yellow-500 border border-yellow-500/30' : 'bg-[--elevated] text-[--text-secondary] border border-[--border]'">
                  {{ status.claimed ? (gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? 'Claimed') : 'Available' }}
                </span>
              </div>
            </div>
          </Card>

          <Card class="flex-1 !p-0 overflow-hidden flex flex-col max-h-[500px]">
            <div class="p-4 border-b border-[--border] bg-[--surface]/50">
              <h2 class="font-bold flex items-center gap-2"><span class="text-lg">👥</span> Live Players</h2>
            </div>
            <div class="flex-1 overflow-y-auto p-2">
              <div class="flex flex-col gap-1">
                <div v-for="p in gameStore.players" :key="p.user_id" class="flex flex-col gap-2 p-3 rounded-xl hover:bg-[--surface] transition-colors border border-transparent hover:border-[--border]">
                  <div class="flex items-center gap-3">
                    <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
                    <span class="flex-1 font-medium">{{ p.name }}</span>
                    <span v-if="p.bogeys" class="px-2 py-0.5 rounded-full bg-red-500/10 text-red-500 text-xs font-bold ring-1 ring-red-500/30">{{ p.bogeys }} Bogey</span>
                  </div>
                  <div v-if="p.prizes_won.length" class="flex flex-wrap gap-1 pl-11">
                    <span v-for="prize in p.prizes_won" :key="prize" class="text-[10px] px-2 py-0.5 bg-yellow-500/10 text-yellow-500 rounded border border-yellow-500/20 uppercase font-bold tracking-wider">
                      {{ prize.replace(/_/g, ' ') }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </Card>
        </div>
      </div>

      <!-- FINISHED -->
      <div v-else-if="gameStore.status === 'finished'" class="flex flex-col items-center justify-center py-12 animate-fade-in-up">
        <div class="w-32 h-32 mb-6 relative">
          <div class="absolute inset-0 bg-yellow-500 rounded-full mix-blend-multiply filter blur-2xl opacity-50 animate-pulse"></div>
          <div class="relative w-full h-full bg-gradient-to-br from-yellow-400 to-yellow-600 rounded-full flex items-center justify-center text-6xl shadow-[0_0_50px_rgba(251,191,36,0.5)]">
            🎉
          </div>
        </div>
        
        <h2 class="text-5xl font-extrabold mb-8 text-transparent bg-clip-text bg-gradient-to-r from-yellow-400 to-amber-600">Game Over!</h2>
        
        <Card class="w-full max-w-2xl bg-[--surface]/80 backdrop-blur-2xl border-yellow-500/30 shadow-2xl p-8 mb-10">
          <h3 class="mb-6 font-bold text-2xl text-center">Final Results</h3>
          <div class="flex flex-col gap-4">
            <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex items-center justify-between p-4 rounded-xl bg-[--bg] border border-[--border] shadow-sm transition-all hover:scale-[1.02]">
              <span class="font-bold text-lg px-3 py-1 bg-gradient-to-r from-yellow-500/20 to-transparent rounded-l-lg capitalize">{{ prize.replace(/_/g, ' ') }}</span>
              <div class="flex items-center gap-3">
                <span v-if="status.claimed" class="font-bold text-lg text-yellow-500">
                  {{ gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? 'Unknown Player' }}
                </span>
                <span v-else class="text-[--text-secondary] italic">Unclaimed</span>
                <Avatar v-if="status.claimed" :name="gameStore.players.find(p => p.user_id === status.winner_id)?.name" :user-id="status.winner_id" size="sm" class="ring-2 ring-yellow-500" />
              </div>
            </div>
          </div>
        </Card>
        
        <div class="flex gap-4">
          <Button class="px-8 py-3 text-lg rounded-full" :loading="loading === 'clone'" @click="action(playAgain, 'clone')">Host Another Game</Button>
          <Button variant="secondary" class="px-8 py-3 text-lg rounded-full" @click="router.push('/')">Return home</Button>
        </div>
      </div>
    </main>

    <div v-if="actionError" class="fixed bottom-6 right-6 z-50 bg-red-500/90 backdrop-blur-md text-white px-6 py-4 rounded-xl shadow-2xl animate-bounce-in max-w-sm border border-red-400">
      <div class="flex gap-3">
        <span class="text-xl">⚠️</span>
        <div>
          <h4 class="font-bold">Action Failed</h4>
          <p class="text-sm opacity-90">{{ actionError }}</p>
        </div>
      </div>
    </div>
  </div>
</template>
