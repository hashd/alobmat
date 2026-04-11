<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useChannel } from '@/composables/useChannel'
import { useCountdown } from '@/composables/useCountdown'
import { useConfetti } from '@/composables/useConfetti'
import TicketGrid from '@/components/game/TicketGrid.vue'
import Board from '@/components/game/Board.vue'
import CountdownRing from '@/components/game/CountdownRing.vue'
import ActivityFeed from '@/components/game/ActivityFeed.vue'
import ReactionOverlay from '@/components/game/ReactionOverlay.vue'
import ConnectionStatus from '@/components/ui/ConnectionStatus.vue'
import BottomSheet from '@/components/ui/BottomSheet.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import Avatar from '@/components/ui/Avatar.vue'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const code = route.params.code as string
import { api } from '@/api/client'

const { gameStore, strike, claim, sendReaction, sendChat, onReaction, connect, claimRejection, joinError } = useChannel(code)
const { secondsLeft, start: startCountdown } = useCountdown(() => gameStore.nextPickAt)
const { fire: fireConfetti } = useConfetti()

const ticketRef = ref<InstanceType<typeof TicketGrid> | null>(null)
const reactionRef = ref<InstanceType<typeof ReactionOverlay> | null>(null)
const boardOpen = ref(false)

const isDev = import.meta.env.DEV

onMounted(async () => {
  if (!auth.isAuthenticated && isDev) {
    try {
      const { token, user } = await api.auth.devLogin()
      auth.login(user, token)
      connect()
    } catch (e) {
      console.warn('Dev login failed', e)
    }
  }
  startCountdown()
})

const myId = computed(() => auth.user?.id)
const myPrizesWon = computed(() =>
  Object.entries(gameStore.prizes)
    .filter(([, s]) => s.winner_id === myId.value)
    .map(([p]) => p)
)

const unsubAction = gameStore.$onAction(({ name, args }) => {
  if (name === 'onStrikeConfirmed' && ticketRef.value) {
    ticketRef.value.onStrikeResult(args[0].number, args[0].result)
  }
  if (name === 'onPrizeClaimed' && (args[0] as any).winner_id === myId.value) {
    fireConfetti()
  }
})
onUnmounted(() => unsubAction())

onReaction((r) => reactionRef.value?.addReaction(r.emoji))

const reactions = ['👏','🎉','🔥','😮','❤️']

const joinSecretInput = ref('')
const isRetrying = ref(false)
async function retryJoin() {
  isRetrying.value = true
  connect(joinSecretInput.value)
  isRetrying.value = false
}
</script>
<template>
  <div class="flex flex-col h-screen bg-[--bg] text-[--text-primary] relative overflow-hidden">
    <!-- Immersive Background Effect -->
    <div v-if="gameStore.status === 'running'" class="absolute inset-0 bg-indigo-500/5 mix-blend-screen pointer-events-none transition-opacity duration-1000"></div>

    <!-- Header -->
    <header class="relative z-10 flex items-center gap-4 border-b border-[--border] bg-[--surface]/80 backdrop-blur-xl px-4 py-3 shadow-[0_4px_30px_rgb(0,0,0,0.05)]">
      <Button variant="ghost" @click="router.push('/')" class="!p-2 rounded-full hover:bg-[--elevated]"><span class="text-xl leading-none">←</span></Button>
      <div class="flex flex-col flex-1">
        <div class="flex items-center gap-2">
          <span class="font-mono font-bold tracking-[0.2em] text-indigo-500 uppercase text-lg">{{ code }}</span>
        </div>
      </div>
      <div class="flex items-center gap-3">
        <Badge :variant="gameStore.status as any" class="shadow-sm font-bold tracking-wider px-3">{{ gameStore.status }}</Badge>
        <div class="flex items-center gap-1.5 text-sm font-medium text-[--text-secondary] bg-[--elevated] px-3 py-1 rounded-full border border-[--border]">
          <span class="text-lg">👥</span> {{ gameStore.players.length }}
        </div>
      </div>
    </header>

    <!-- Connecting state -->
    <div v-if="joinError === 'invalid_secret'" class="flex flex-1 flex-col items-center justify-center gap-6 p-6 animate-fade-in-up">
      <div class="text-4xl mb-2">🔒</div>
      <h2 class="text-2xl font-bold">Private Game</h2>
      <p class="text-[--text-secondary] text-center max-w-sm mb-4">This game requires a secret code to join. Please enter it below.</p>
      
      <div class="flex items-center gap-2 max-w-sm w-full">
        <input v-model="joinSecretInput" @keyup.enter="retryJoin" type="password" placeholder="Enter secret code" class="flex-1 rounded-xl border border-[--border] bg-[--surface] px-4 py-3 focus:ring-2 focus:ring-indigo-500 outline-none" />
        <Button :loading="isRetrying" @click="retryJoin" class="px-6 py-3 rounded-xl shadow-md">Join directly</Button>
      </div>
      <Button variant="ghost" @click="router.push('/')">Go Back</Button>
    </div>

    <!-- Connecting state -->
    <div v-else-if="!gameStore.hydrated && !joinError" class="flex flex-1 flex-col items-center justify-center gap-6 p-6">
      <div class="w-16 h-16 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin"></div>
      <p class="text-[--text-secondary] font-medium text-lg animate-pulse">Entering game room...</p>
    </div>

    <!-- Error state -->
    <div v-else-if="!gameStore.hydrated && joinError" class="flex flex-1 flex-col items-center justify-center gap-6 p-6">
      <h2 class="text-2xl font-bold text-red-500">Failed to Connect</h2>
      <p class="text-[--text-secondary]">{{ joinError }}</p>
      <Button @click="router.push('/')">Return home</Button>
    </div>

    <!-- Lobby state -->
    <div v-else-if="gameStore.status === 'lobby'" class="flex flex-1 flex-col items-center justify-center gap-6 p-4 md:p-6 overflow-y-auto w-full max-w-3xl mx-auto animate-fade-in-up">
      <div class="text-center max-w-sm mt-4">
        <div class="text-5xl md:text-6xl mb-4 animate-bounce-in">⏳</div>
        <h2 class="text-2xl font-bold mb-2">Waiting for Host</h2>
        <p class="text-[--text-secondary]">The game will begin shortly. Hang tight!</p>
      </div>
      
      <!-- Show their ticket early -->
      <div class="w-full flex flex-col gap-3">
        <h3 class="font-bold text-center text-[--text-secondary] uppercase tracking-wider text-sm">Your Ticket for this Game</h3>
        <div class="relative bg-[--surface]/40 backdrop-blur-xl p-4 md:p-6 rounded-3xl border border-[--border] shadow-[0_8px_40px_rgb(0,0,0,0.04)] mb-4">
          <TicketGrid
            v-if="gameStore.myTicket"
            :ticket="gameStore.myTicket"
            :struck="gameStore.myStruck"
            :picked-numbers="gameStore.board.picks"
            :interactive="false"
          />
        </div>
      </div>
      
      <div class="w-full bg-[--surface]/50 backdrop-blur-md rounded-2xl border border-[--border] p-6 shadow-sm">
        <h3 class="font-bold mb-4 flex items-center gap-2">Players Ready <span class="bg-indigo-500/10 text-indigo-500 px-2 py-0.5 rounded-full text-xs">{{ gameStore.players.length }}</span></h3>
        <div class="flex flex-wrap gap-2">
          <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-2 rounded-full border border-[--border] bg-[--bg] px-3 py-1.5 text-sm shadow-sm transition-all hover:scale-105">
            <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
            <span class="font-medium" :class="{ 'text-indigo-500': p.user_id === myId }">{{ p.user_id === myId ? p.name + ' (You)' : p.name }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Running/paused state -->
    <div v-else-if="['running','paused'].includes(gameStore.status)" class="flex flex-1 overflow-hidden">
      <!-- Main area -->
      <div class="flex flex-1 flex-col gap-6 overflow-y-auto p-4 md:p-6 pb-32">
        <div class="flex flex-col md:flex-row gap-6 max-w-5xl mx-auto w-full">
          <!-- Left Column: Status & Ticket -->
          <div class="flex flex-1 flex-col gap-6">
            <div class="flex items-center justify-between bg-[--surface]/60 backdrop-blur-md rounded-2xl border border-[--border] p-5 shadow-sm">
              <div class="flex items-center gap-6">
                <!-- Last picked number -->
                <div v-if="gameStore.board.picks.length" class="text-center relative">
                  <div class="w-20 h-20 bg-gradient-to-br from-indigo-500 to-purple-600 rounded-full flex items-center justify-center shadow-[0_0_30px_rgba(99,102,241,0.4)] text-white font-black text-4xl mb-1">
                    {{ gameStore.board.picks[gameStore.board.picks.length - 1] }}
                  </div>
                  <span class="text-xs font-bold text-[--text-secondary] uppercase tracking-wider">Latest</span>
                </div>
                
                <div class="flex flex-col gap-1">
                  <p class="text-sm font-bold text-[--text-secondary] uppercase tracking-wider">Progress</p>
                  <p class="text-2xl font-bold font-mono">{{ gameStore.board.count }} <span class="text-[--text-muted] text-lg">/ 90</span></p>
                </div>
              </div>
              
              <!-- Countdown -->
              <div v-if="gameStore.status === 'running'" class="flex flex-col items-center">
                <CountdownRing :seconds-left="secondsLeft" :total-seconds="gameStore.settings.interval" />
                <span class="text-[10px] font-bold text-[--text-secondary] uppercase tracking-wider mt-1">Next</span>
              </div>
              <div v-else class="text-indigo-500 font-bold px-4 py-2 bg-indigo-500/10 rounded-xl border border-indigo-500/20">PAUSED</div>
            </div>

            <!-- Ticket -->
            <div class="relative bg-[--surface]/40 backdrop-blur-xl p-4 md:p-6 rounded-3xl border border-[--border] shadow-[0_8px_40px_rgb(0,0,0,0.04)] flex flex-col gap-4">
              <div class="flex items-center justify-between">
                <span class="text-sm font-bold text-[--text-secondary] uppercase tracking-wider">Your Ticket</span>
                <label class="flex items-center gap-2 cursor-pointer group">
                  <span class="text-xs font-bold text-[--text-secondary] uppercase tracking-wider group-hover:text-indigo-500 transition-colors">Auto Strike</span>
                  <div class="relative">
                    <input type="checkbox" v-model="gameStore.autoStrikeEnabled" class="sr-only peer" />
                    <div class="w-9 h-5 bg-[--border] peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-indigo-500"></div>
                  </div>
                </label>
              </div>
              <TicketGrid
                v-if="gameStore.myTicket"
                ref="ticketRef"
                :ticket="gameStore.myTicket"
                :struck="gameStore.myStruck"
                :picked-numbers="gameStore.board.picks"
                :interactive="gameStore.status === 'running'"
                @strike="strike"
              />
            </div>
          </div>

          <!-- Right Column: Prizes (Mobile layout puts this below ticket) -->
          <div class="w-full md:w-72 flex flex-col gap-4">
            <!-- Prizes -->
            <Card class="!p-4 bg-gradient-to-br from-yellow-500/5 to-transparent border-yellow-500/20">
              <h3 class="font-bold mb-4 flex items-center justify-between text-yellow-600 dark:text-yellow-500">
                <span>Prizes</span>
                <span class="text-2xl">🏆</span>
              </h3>
              <div class="flex flex-col gap-2">
                <button
                  v-for="(status, prize) in gameStore.prizes"
                  :key="prize"
                  @click="!status.claimed && claim(prize)"
                  :disabled="status.claimed"
                  class="relative overflow-hidden w-full text-left px-4 py-3 rounded-xl border transition-all duration-300 font-bold flex items-center justify-between group"
                  :class="[
                    status.claimed ? 'border-yellow-500/20 bg-yellow-500/5 text-yellow-600/50 dark:text-yellow-400/50 cursor-not-allowed' :
                    myPrizesWon.includes(prize) ? 'border-green-500 bg-green-500/10 text-green-600 dark:text-green-400 shadow-[0_0_20px_rgba(16,185,129,0.2)]' :
                    'border-[--border] bg-[--surface] text-[--text-primary] hover:border-indigo-500 hover:shadow-[0_4px_15px_rgba(99,102,241,0.15)] hover:-translate-y-0.5'
                  ]"
                >
                  <span class="capitalize z-10">{{ prize.replace(/_/g, ' ') }}</span>
                  
                  <span v-if="status.claimed" class="z-10 text-xs px-2 py-1 bg-yellow-500/10 rounded-md">{{ myPrizesWon.includes(prize) ? 'You Won!' : 'Claimed' }}</span>
                  <span v-else class="z-10 text-xs px-3 py-1 bg-indigo-500 text-white rounded-full opacity-0 translate-x-2 group-hover:opacity-100 group-hover:translate-x-0 transition-all">Claim</span>
                  
                  <div v-if="myPrizesWon.includes(prize)" class="absolute inset-0 bg-gradient-to-r from-green-400/20 to-emerald-500/20 pointer-events-none"></div>
                </button>
              </div>
            </Card>
          </div>
        </div>
      </div>

      <!-- Activity feed (desktop) -->
      <div class="hidden w-80 border-l border-[--border] bg-[--bg]/50 backdrop-blur-xl p-0 md:flex flex-col">
        <ActivityFeed @send-chat="sendChat" />
      </div>

      <!-- Floating Action Bar (Mobile Bottom) -->
      <div class="fixed bottom-6 left-1/2 -translate-x-1/2 z-40 w-[90%] max-w-sm rounded-full bg-[--surface]/90 backdrop-blur-xl border border-[--border] shadow-[0_10px_40px_rgba(0,0,0,0.1)] p-2">
        <div class="flex items-center justify-between">
          <Button variant="ghost" class="!px-4 !py-2 rounded-full basis-1/3 text-sm font-bold" @click="boardOpen = true">
            <span class="flex items-center gap-2">Board <span class="text-xs bg-indigo-500 text-white px-1.5 py-0.5 rounded-md">{{ gameStore.board.count }}</span></span>
          </Button>
          <div class="h-8 w-[1px] bg-[--border]"></div>
          <div class="flex items-center justify-evenly basis-2/3 px-2">
            <button v-for="e in reactions" :key="e" @click="sendReaction(e)"
              class="text-2xl hover:scale-150 transition-transform origin-bottom duration-300">{{ e }}</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Finished state -->
    <div v-else-if="gameStore.status === 'finished'" class="flex flex-1 flex-col items-center justify-center gap-6 p-6 animate-fade-in-up">
      <div class="w-32 h-32 mb-2 relative">
        <div class="absolute inset-0 bg-yellow-500 rounded-full mix-blend-multiply filter blur-2xl opacity-50 animate-pulse"></div>
        <div class="relative w-full h-full bg-gradient-to-br from-yellow-400 to-yellow-600 rounded-full flex items-center justify-center text-6xl shadow-[0_0_50px_rgba(251,191,36,0.5)] border-4 border-yellow-300">
          🏆
        </div>
      </div>
      
      <h2 class="text-4xl md:text-5xl font-black mb-4 text-transparent bg-clip-text bg-gradient-to-r from-yellow-400 to-amber-600 text-center leading-tight">Game Complete</h2>
      
      <Card class="w-full max-w-xl bg-[--surface]/80 backdrop-blur-2xl border-yellow-500/30 border-t-4 border-t-yellow-500 shadow-2xl p-6 md:p-8 mb-6">
        <h3 class="mb-6 font-bold text-xl text-center uppercase tracking-widest text-[--text-secondary]">Winners Circle</h3>
        <div class="flex flex-col gap-3">
          <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex items-center justify-between p-3 md:p-4 rounded-xl bg-[--bg] border border-[--border] shadow-sm">
            <span class="font-bold text-sm md:text-lg capitalize text-yellow-600 dark:text-yellow-400">{{ prize.replace(/_/g, ' ') }}</span>
            <div class="flex items-center gap-3">
              <span class="font-bold text-sm md:text-lg" :class="status.winner_id === myId ? 'text-green-500' : 'text-[--text-primary]'">
                {{ status.winner_id ? (status.winner_id === myId ? 'You!' : gameStore.players.find(p => p.user_id === status.winner_id)?.name) : '—' }}
              </span>
              <Avatar v-if="status.winner_id" :name="gameStore.players.find(p => p.user_id === status.winner_id)?.name" :user-id="status.winner_id" size="sm" :class="{'ring-2 ring-green-500': status.winner_id === myId}" />
            </div>
          </div>
        </div>
      </Card>
      <Button class="px-10 py-3 text-lg rounded-full" @click="router.push('/')">Return to Home</Button>
    </div>

    <!-- Claim rejection toast -->
    <Transition name="fade">
      <div v-if="claimRejection" class="fixed top-8 left-1/2 -translate-x-1/2 z-[60] rounded-2xl bg-red-600/90 backdrop-blur-md px-6 py-4 text-sm text-white shadow-[0_10px_40px_rgba(220,38,38,0.4)] border border-red-500 flex items-center gap-3 font-bold">
        <span class="text-2xl">🚨</span>
        {{ claimRejection.reason === 'bogey'
          ? `Bogey! You have ${claimRejection.bogeys_remaining} strikes remaining`
          : claimRejection.reason.replace(/_/g, ' ') }}
      </div>
    </Transition>

    <!-- Board bottom sheet -->
    <BottomSheet :open="boardOpen" title="All numbers" @close="boardOpen = false">
      <div class="p-4 bg-[--surface]/50 rounded-2xl border border-[--border]">
        <Board :picks="gameStore.board.picks" />
      </div>
    </BottomSheet>

    <!-- Reaction overlay -->
    <ReactionOverlay ref="reactionRef" />

    <!-- Connection status -->
    <ConnectionStatus :connected="gameStore.channelConnected" />
  </div>
</template>
