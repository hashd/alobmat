<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
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

const { gameStore, strike, claim, sendReaction, sendChat, onReaction } = useChannel(code)
const { secondsLeft, start: startCountdown } = useCountdown(() => gameStore.nextPickAt)
const { fire: fireConfetti } = useConfetti()

const ticketRef = ref<InstanceType<typeof TicketGrid> | null>(null)
const reactionRef = ref<InstanceType<typeof ReactionOverlay> | null>(null)
const boardOpen = ref(false)

onMounted(() => startCountdown())

const myId = computed(() => auth.user?.id)
const myPrizesWon = computed(() =>
  Object.entries(gameStore.prizes)
    .filter(([, s]) => s.winner_id === myId.value)
    .map(([p]) => p)
)

gameStore.$onAction(({ name, args }) => {
  if (name === 'onStrikeConfirmed' && ticketRef.value) {
    ticketRef.value.onStrikeResult(args[0].number, args[0].result)
  }
  if (name === 'onPrizeClaimed' && (args[0] as any).winner_id === myId.value) {
    fireConfetti()
  }
})

onReaction((r) => reactionRef.value?.addReaction(r.emoji))

const reactions = ['👏','🎉','🔥','😮','❤️']
</script>
<template>
  <div class="flex flex-col h-screen bg-[--bg] text-[--text-primary]">
    <!-- Header -->
    <div class="flex items-center gap-3 border-b border-[--border] px-4 py-3">
      <Button variant="ghost" @click="router.push('/')">←</Button>
      <span class="font-mono font-bold tracking-widest">{{ code }}</span>
      <Badge :variant="gameStore.status as any">{{ gameStore.status }}</Badge>
      <span class="ml-auto text-sm text-[--text-secondary]">{{ gameStore.players.length }} players</span>
    </div>

    <!-- Lobby state -->
    <div v-if="gameStore.status === 'lobby'" class="flex flex-1 flex-col items-center justify-center gap-4 p-6">
      <p class="text-[--text-secondary]">Waiting for host to start…</p>
      <div class="flex flex-wrap gap-2">
        <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-2 rounded-full border border-[--border] px-3 py-1 text-sm">
          <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
          {{ p.name }}
        </div>
      </div>
    </div>

    <!-- Running/paused state -->
    <div v-else-if="['running','paused'].includes(gameStore.status)" class="flex flex-1 overflow-hidden">
      <!-- Main area -->
      <div class="flex flex-1 flex-col gap-4 overflow-y-auto p-4">
        <!-- Countdown -->
        <div v-if="gameStore.status === 'running'" class="flex justify-center">
          <CountdownRing :seconds-left="secondsLeft" :total-seconds="gameStore.settings.interval" />
        </div>
        <div v-else class="text-center text-[--text-secondary]">Game paused</div>

        <!-- Last picked number -->
        <div v-if="gameStore.board.picks.length" class="text-center">
          <span class="text-5xl font-bold">{{ gameStore.board.picks[gameStore.board.picks.length - 1] }}</span>
          <p class="text-sm text-[--text-secondary]">{{ gameStore.board.count }} / 90</p>
        </div>

        <!-- Ticket -->
        <TicketGrid
          v-if="gameStore.myTicket"
          ref="ticketRef"
          :ticket="gameStore.myTicket"
          :struck="gameStore.myStruck"
          :picked-numbers="gameStore.board.picks"
          :interactive="gameStore.status === 'running'"
          @strike="strike"
        />

        <!-- Prizes -->
        <div class="flex flex-wrap gap-2">
          <button
            v-for="(status, prize) in gameStore.prizes"
            :key="prize"
            @click="!status.claimed && claim(prize)"
            :disabled="status.claimed"
            :class="['rounded-full border px-3 py-1 text-xs font-medium transition-all',
              status.claimed ? 'border-yellow-500/30 bg-yellow-500/10 text-yellow-400' :
              myPrizesWon.includes(prize) ? 'border-green-500 bg-green-500/10 text-green-400' :
              'border-[--border] text-[--text-secondary] hover:border-[--accent]']"
          >{{ prize.replace(/_/g, ' ') }} {{ status.claimed ? '✓' : '' }}</button>
        </div>

        <!-- Reactions -->
        <div class="flex gap-2">
          <button v-for="e in reactions" :key="e" @click="sendReaction(e)"
            class="text-xl hover:scale-125 transition-transform">{{ e }}</button>
        </div>

        <!-- View full board -->
        <Button variant="ghost" @click="boardOpen = true">View board ({{ gameStore.board.count }}/90)</Button>
      </div>

      <!-- Activity feed (desktop) -->
      <div class="hidden w-72 border-l border-[--border] p-4 md:flex flex-col">
        <ActivityFeed @send-chat="sendChat" />
      </div>
    </div>

    <!-- Finished state -->
    <div v-else-if="gameStore.status === 'finished'" class="flex flex-1 flex-col items-center justify-center gap-4 p-6">
      <h2 class="text-2xl font-bold">Game over!</h2>
      <div class="flex flex-col gap-2 w-full max-w-sm">
        <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex justify-between text-sm border-b border-[--border] py-2">
          <span>{{ prize.replace(/_/g, ' ') }}</span>
          <span class="text-[--text-secondary]">{{ status.winner_id ? gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? status.winner_id : '—' }}</span>
        </div>
      </div>
      <Button @click="router.push('/')">Home</Button>
    </div>

    <!-- Board bottom sheet -->
    <BottomSheet :open="boardOpen" title="All numbers" @close="boardOpen = false">
      <Board :picks="gameStore.board.picks" />
    </BottomSheet>

    <!-- Reaction overlay -->
    <ReactionOverlay ref="reactionRef" />

    <!-- Connection status -->
    <ConnectionStatus :connected="gameStore.channelConnected" />
  </div>
</template>
