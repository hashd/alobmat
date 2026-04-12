<script setup lang="ts">
import { ref, computed } from 'vue'
import type { PrizeStatus, Ticket } from '@/types/domain'

const props = defineProps<{
  prizes: Record<string, PrizeStatus>
  myId: string | undefined
  tickets: Ticket[]
  gameRunning: boolean
}>()

const emit = defineEmits<{ claim: [prize: string, ticketId: string] }>()

const prizeLabel: Record<string, string> = {
  early_five: 'Early Five',
  top_line: 'Top Line',
  middle_line: 'Middle Line',
  bottom_line: 'Bottom Line',
  full_house: 'Full House',
}

const prizeOrder = ['early_five', 'top_line', 'middle_line', 'bottom_line', 'full_house']

const sortedPrizes = computed(() => {
  return prizeOrder
    .filter(p => p in props.prizes)
    .map(p => ({
      key: p,
      label: prizeLabel[p] ?? p.replace(/_/g, ' '),
      status: props.prizes[p],
      isClaimed: props.prizes[p]?.claimed ?? false,
      isMyWin: props.prizes[p]?.winner_id === props.myId,
    }))
})

// ── Ticket picker state ──────────────────────────────────────────────────
const pickingPrize = ref<string | null>(null)

function handleClaim(prizeKey: string) {
  if (props.tickets.length === 1) {
    // Single ticket — claim directly
    emit('claim', prizeKey, props.tickets[0].id)
  } else {
    // Multi-ticket — show picker
    pickingPrize.value = prizeKey
  }
}

function selectTicket(ticketId: string) {
  if (pickingPrize.value) {
    emit('claim', pickingPrize.value, ticketId)
    pickingPrize.value = null
  }
}

function cancelPick() {
  pickingPrize.value = null
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-for="prize in sortedPrizes"
      :key="prize.key"
      class="flex items-center justify-between px-4 py-3 rounded-xl border transition-all duration-300 group"
      :class="[
        prize.isMyWin
          ? 'bg-green-500/10 border-green-500/30 shadow-[0_0_15px_rgba(16,185,129,0.1)]'
          : prize.isClaimed
            ? 'bg-[--surface]/30 border-[--border]/40 opacity-60'
            : 'bg-[--surface] border-[--border] hover:border-indigo-500/40'
      ]"
    >
      <span
        class="font-bold text-sm capitalize"
        :class="[
          prize.isMyWin ? 'text-green-500' :
          prize.isClaimed ? 'text-[--text-muted]' :
          'text-[--text-primary]'
        ]"
      >{{ prize.label }}</span>

      <!-- Claim button -->
      <button
        v-if="!prize.isClaimed && gameRunning"
        @click="handleClaim(prize.key)"
        class="px-3 py-1 rounded-lg text-xs font-black uppercase tracking-wider
               bg-gradient-to-r from-indigo-500 to-purple-600 text-white
               shadow-sm hover:shadow-[0_4px_15px_rgba(99,102,241,0.4)]
               hover:scale-105 active:scale-95 transition-all duration-200"
      >
        Claim
      </button>

      <!-- Status badges -->
      <span v-else-if="prize.isMyWin"
        class="px-2.5 py-1 rounded-lg text-[10px] font-black uppercase tracking-wider bg-green-500/20 text-green-500 border border-green-500/30 flex items-center gap-1"
      >✓ You Won!</span>

      <span v-else-if="prize.isClaimed"
        class="px-2.5 py-1 rounded-lg text-[10px] font-bold uppercase tracking-wider bg-[--elevated] text-[--text-muted] border border-[--border]/50"
      >Claimed</span>
    </div>

    <!-- Ticket picker overlay -->
    <Transition name="fade">
      <div v-if="pickingPrize" class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" @click.self="cancelPick">
        <div class="bg-[--surface] border border-[--border] rounded-2xl shadow-2xl p-6 max-w-sm w-full mx-4 animate-bounce-in">
          <h3 class="font-bold text-lg mb-1">Claim {{ prizeLabel[pickingPrize] || pickingPrize }}</h3>
          <p class="text-sm text-[--text-secondary] mb-4">Which ticket do you want to claim with?</p>

          <div class="flex flex-col gap-2">
            <button
              v-for="(ticket, i) in tickets"
              :key="ticket.id"
              @click="selectTicket(ticket.id)"
              class="flex items-center gap-3 px-4 py-3 rounded-xl border border-[--border] bg-[--bg]
                     hover:border-indigo-500 hover:shadow-[0_4px_15px_rgba(99,102,241,0.15)]
                     hover:-translate-y-0.5 active:scale-[0.98] transition-all duration-200 text-left"
            >
              <span class="w-8 h-8 rounded-lg bg-indigo-500/15 text-indigo-500 flex items-center justify-center text-sm font-black shrink-0">{{ i + 1 }}</span>
              <div class="flex-1 min-w-0">
                <span class="font-bold text-sm">Ticket {{ i + 1 }}</span>
                <span class="text-xs text-[--text-secondary] ml-2 font-mono">{{ ticket.numbers.length }} numbers</span>
              </div>
              <span class="text-indigo-500 text-lg">→</span>
            </button>
          </div>

          <button @click="cancelPick" class="w-full mt-4 py-2 text-sm font-bold text-[--text-secondary] hover:text-[--text-primary] transition-colors">Cancel</button>
        </div>
      </div>
    </Transition>
  </div>
</template>
