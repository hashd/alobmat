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
import NumberCallOverlay from '@/components/game/NumberCallOverlay.vue'
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

const ticketRefs = ref<(InstanceType<typeof TicketGrid> | null)[]>([])
function setTicketRef(el: any, index: number) { ticketRefs.value[index] = el as InstanceType<typeof TicketGrid> | null }
const reactionRef = ref<InstanceType<typeof ReactionOverlay> | null>(null)
const numberCallRef = ref<InstanceType<typeof NumberCallOverlay> | null>(null)
const boardOpen = ref(false)
const activityOpen = ref(false)

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

// ── Claim modal state ─────────────────────────────────────────────────────────
const claimingTicketId = ref<string | null>(null)
const claimingTicketIndex = ref<number>(0)

const prizeLabel: Record<string, string> = {
  early_five: 'Early Five',
  top_line: 'Top Line',
  middle_line: 'Middle Line',
  bottom_line: 'Bottom Line',
  full_house: 'Full House',
}
const prizeOrder = ['early_five', 'top_line', 'middle_line', 'bottom_line', 'full_house']

const availablePrizes = computed(() =>
  prizeOrder
    .filter(p => p in gameStore.prizes && !gameStore.prizes[p].claimed)
    .map(p => ({ key: p, label: prizeLabel[p] ?? p.replace(/_/g, ' ') }))
)

function openClaimModal(ticketId: string, index: number) {
  claimingTicketId.value = ticketId
  claimingTicketIndex.value = index
}

function submitClaim(prizeKey: string) {
  if (claimingTicketId.value) {
    claim(prizeKey, claimingTicketId.value)
    claimingTicketId.value = null
  }
}

function closeClaimModal() {
  claimingTicketId.value = null
}

const unsubAction = gameStore.$onAction(({ name, args, after }) => {
  if (name === 'onStrikeConfirmed') {
    ticketRefs.value.forEach(r => r?.onStrikeResult(args[0].number, args[0].result))
  }
  if (name === 'onPrizeClaimed' && (args[0] as any).winner_id === myId.value) {
    fireConfetti()
  }
  if (name === 'onPick') {
    const event = args[0] as any
    after(() => {
      const isOnTicket = gameStore.myTickets.some(t => t.numbers.includes(event.number))
      const interval = gameStore.settings.interval
      const durationMs = Math.max(1000, Math.min(3000, (interval - 1) * 1000))
      numberCallRef.value?.show(event.number, isOnTicket, durationMs)
    })
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
      
      <!-- Show their tickets early -->
      <div class="w-full flex flex-col gap-3">
        <h3 class="font-bold text-center text-[--text-secondary] uppercase tracking-wider text-sm">Your Ticket{{ gameStore.myTickets.length > 1 ? 's' : '' }} for this Game</h3>
        <div v-for="(ticket, i) in gameStore.myTickets" :key="ticket.id" class="relative bg-[--surface]/40 backdrop-blur-xl p-4 md:p-6 rounded-3xl border border-[--border] shadow-[0_8px_40px_rgb(0,0,0,0.04)]">
          <p v-if="gameStore.myTickets.length > 1" class="text-xs font-bold text-[--text-secondary] uppercase tracking-wider mb-3">Ticket {{ i + 1 }}</p>
          <TicketGrid
            :ticket="ticket"
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
        <div class="flex flex-col gap-6 max-w-3xl mx-auto w-full">
          <!-- Status bar -->
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

          <!-- Tickets -->
          <div class="flex flex-col gap-6">
            <div v-for="(ticket, i) in gameStore.myTickets" :key="ticket.id"
              class="relative bg-[--surface]/40 backdrop-blur-xl p-4 md:p-6 rounded-3xl border border-[--border] shadow-[0_8px_40px_rgb(0,0,0,0.04)]"
            >
              <!-- Ticket header -->
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                  <span v-if="gameStore.myTickets.length > 1" class="w-6 h-6 rounded-lg bg-indigo-500/20 text-indigo-400 flex items-center justify-center text-xs font-black">{{ i + 1 }}</span>
                  <span class="text-sm font-bold text-[--text-secondary] uppercase tracking-wider">
                    {{ gameStore.myTickets.length > 1 ? `Ticket ${i + 1}` : 'Your Ticket' }}
                  </span>
                </div>
                <div class="flex items-center gap-2">
                  <!-- Auto Strike toggle (only on first ticket) -->
                  <label v-if="i === 0" class="flex items-center gap-2 cursor-pointer group">
                    <span class="text-xs font-bold text-[--text-secondary] uppercase tracking-wider group-hover:text-indigo-500 transition-colors">Auto Strike</span>
                    <div class="relative">
                      <input type="checkbox" v-model="gameStore.autoStrikeEnabled" class="sr-only peer" />
                      <div class="w-9 h-5 bg-[--border] peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-indigo-500"></div>
                    </div>
                  </label>
                  <!-- Claim button -->
                  <button
                    v-if="gameStore.status === 'running' && availablePrizes.length > 0"
                    @click="openClaimModal(ticket.id, i)"
                    class="flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-black uppercase tracking-wider
                           bg-gradient-to-r from-yellow-400 to-amber-500 text-yellow-950
                           shadow-[0_2px_12px_rgba(251,191,36,0.35)]
                           hover:shadow-[0_4px_20px_rgba(251,191,36,0.5)] hover:scale-105
                           active:scale-95 transition-all duration-200"
                  >
                    <span>🏆</span> Claim
                  </button>
                </div>
              </div>

              <TicketGrid
                :ref="(el) => setTicketRef(el, i)"
                :ticket="ticket"
                :struck="gameStore.myStruck"
                :picked-numbers="gameStore.board.picks"
                :interactive="gameStore.status === 'running'"
                @strike="strike"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Activity feed slide-in overlay -->
      <Transition name="slide-right">
        <div v-if="activityOpen" class="fixed inset-0 z-40 flex justify-end" @click.self="activityOpen = false">
          <div class="absolute inset-0 bg-black/30 backdrop-blur-[2px]" @click="activityOpen = false"></div>
          <div class="relative w-full max-w-sm h-full bg-[--bg] border-l border-[--border] shadow-[-10px_0_40px_rgba(0,0,0,0.15)] flex flex-col">
            <ActivityFeed @send-chat="sendChat" @close="activityOpen = false" class="flex-1" />
          </div>
        </div>
      </Transition>

      <!-- Floating Action Bar -->
      <div class="fixed bottom-6 left-1/2 -translate-x-1/2 z-30 w-[90%] max-w-sm rounded-full bg-[--surface]/90 backdrop-blur-xl border border-[--border] shadow-[0_10px_40px_rgba(0,0,0,0.1)] p-2">
        <div class="flex items-center justify-between">
          <Button variant="ghost" class="!px-4 !py-2 rounded-full text-sm font-bold" @click="boardOpen = true">
            <span class="flex items-center gap-2">Board <span class="text-xs bg-indigo-500 text-white px-1.5 py-0.5 rounded-md">{{ gameStore.board.count }}</span></span>
          </Button>
          <div class="h-8 w-[1px] bg-[--border]"></div>
          <div class="flex items-center justify-evenly flex-1 px-2">
            <button v-for="e in reactions" :key="e" @click="sendReaction(e)"
              class="text-xl hover:scale-150 transition-transform origin-bottom duration-300">{{ e }}</button>
          </div>
          <div class="h-8 w-[1px] bg-[--border]"></div>
          <Button variant="ghost" class="!px-4 !py-2 rounded-full text-sm font-bold" @click="activityOpen = true">
            <span class="flex items-center gap-1">💬</span>
          </Button>
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

    <!-- Claim prize modal -->
    <Transition name="fade">
      <div v-if="claimingTicketId" class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" @click.self="closeClaimModal">
        <div class="bg-[--surface] border border-[--border] rounded-2xl shadow-2xl p-6 max-w-sm w-full mx-4 animate-bounce-in">
          <div class="flex items-center justify-between mb-1">
            <h3 class="font-bold text-lg flex items-center gap-2">
              <span>🏆</span> Claim a Prize
            </h3>
            <button @click="closeClaimModal" class="w-8 h-8 rounded-lg flex items-center justify-center text-[--text-secondary] hover:bg-[--elevated] transition-colors">✕</button>
          </div>
          <p class="text-sm text-[--text-secondary] mb-5">
            Claiming with <span class="font-bold text-[--text-primary]">Ticket {{ claimingTicketIndex + 1 }}</span>
          </p>

          <div v-if="availablePrizes.length" class="flex flex-col gap-2">
            <button
              v-for="prize in availablePrizes"
              :key="prize.key"
              @click="submitClaim(prize.key)"
              class="w-full text-left px-4 py-3.5 rounded-xl border border-[--border] bg-[--bg]
                     hover:border-yellow-500/60 hover:bg-yellow-500/5 hover:shadow-[0_4px_15px_rgba(251,191,36,0.15)]
                     hover:-translate-y-0.5 active:scale-[0.98] transition-all duration-200
                     flex items-center justify-between group"
            >
              <span class="font-bold capitalize">{{ prize.label }}</span>
              <span class="text-xs px-3 py-1 bg-gradient-to-r from-yellow-400 to-amber-500 text-yellow-950 rounded-full font-black uppercase tracking-wider opacity-0 translate-x-2 group-hover:opacity-100 group-hover:translate-x-0 transition-all duration-200">Claim</span>
            </button>
          </div>
          <div v-else class="text-center py-6 text-[--text-secondary]">
            <p class="text-3xl mb-2">🎉</p>
            <p class="font-medium">All prizes have been claimed!</p>
          </div>
        </div>
      </div>
    </Transition>

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

    <!-- Number call overlay -->
    <NumberCallOverlay ref="numberCallRef" />

    <!-- Connection status -->
    <ConnectionStatus :connected="gameStore.channelConnected" />
  </div>
</template>

<style scoped>
.slide-right-enter-active,
.slide-right-leave-active {
  transition: opacity 0.3s ease;
}
.slide-right-enter-active > div:last-child,
.slide-right-leave-active > div:last-child {
  transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}
.slide-right-enter-from,
.slide-right-leave-to {
  opacity: 0;
}
.slide-right-enter-from > div:last-child,
.slide-right-leave-to > div:last-child {
  transform: translateX(100%);
}
</style>
