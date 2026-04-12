import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Board, GameSettings, Player, PrizeProgress, PrizeStatus, Ticket } from '@/types/domain'
import type {
  GameJoinReply, NumberPickedEvent, GameStatusEvent, PrizeClaimedEvent,
  BogeyEvent, PlayerJoinedEvent, PlayerLeftEvent, StrikeResultEvent,
  TicketCountUpdatedEvent, PlayerTicketsUpdatedEvent
} from '@/types/channel'

export const useGameStore = defineStore('game', () => {
  const code = ref('')
  const name = ref('')
  const hostId = ref<string | null>(null)
  const status = ref<string>('lobby')
  const settings = ref<GameSettings>({ interval: 30, bogey_limit: 3, default_ticket_count: 1, enabled_prizes: [] })
  const board = ref<Board>({ picks: [], count: 0, finished: false })
  const myTickets = ref<Ticket[]>([])
  const myStruck = ref<Set<number>>(new Set())
  const players = ref<Player[]>([])
  const prizes = ref<Record<string, PrizeStatus>>({})
  const prizeProgress = ref<Record<string, Record<string, PrizeProgress>>>({})
  const nextPickAt = ref<string | null>(null)
  const channelConnected = ref(false)
  const autoStrikeEnabled = ref(false)

  const hydrated = ref(false)

  // ── Client-side prize progress computation ──────────────────────────────────
  // Mirrors backend's compute_prize_progress so progress updates instantly
  // when numbers are struck, without waiting for server round-trips.

  function lineProgress(row: (number | null)[], struck: Set<number>): PrizeProgress {
    const rowNumbers = row.filter((n): n is number => n !== null)
    const hit = rowNumbers.filter(n => struck.has(n)).length
    return { struck: hit, required: rowNumbers.length }
  }

  function computeTicketProgress(ticket: Ticket, struck: Set<number>, enabledPrizes: string[]): Record<string, PrizeProgress> {
    const progress: Record<string, PrizeProgress> = {}

    for (const prize of enabledPrizes) {
      switch (prize) {
        case 'top_line':
          progress[prize] = lineProgress(ticket.rows[0], struck)
          break
        case 'middle_line':
          progress[prize] = lineProgress(ticket.rows[1], struck)
          break
        case 'bottom_line':
          progress[prize] = lineProgress(ticket.rows[2], struck)
          break
        case 'early_five': {
          const hit = ticket.numbers.filter(n => struck.has(n)).length
          progress[prize] = { struck: Math.min(hit, 5), required: 5 }
          break
        }
        case 'full_house': {
          const total = ticket.numbers.length
          const hit = ticket.numbers.filter(n => struck.has(n)).length
          progress[prize] = { struck: hit, required: total }
          break
        }
      }
    }

    return progress
  }

  const myPrizeProgress = computed<Record<string, Record<string, PrizeProgress>>>(() => {
    const result: Record<string, Record<string, PrizeProgress>> = {}
    const struck = myStruck.value
    const enabledPrizes = settings.value.enabled_prizes

    for (const ticket of myTickets.value) {
      result[ticket.id] = computeTicketProgress(ticket, struck, enabledPrizes)
    }

    return result
  })

  function hydrate(reply: GameJoinReply) {
    code.value = reply.code
    name.value = reply.name
    hostId.value = reply.host_id ?? null
    status.value = reply.status
    settings.value = reply.settings
    board.value = reply.board
    myTickets.value = reply.my_tickets ?? []
    myStruck.value = new Set(reply.my_struck)
    players.value = reply.players
    prizes.value = reply.prizes
    prizeProgress.value = reply.prize_progress
    channelConnected.value = true
    hydrated.value = true
  }

  function onPick(event: NumberPickedEvent, autoStrike?: (n: number) => void) {
    board.value = {
      ...board.value,
      picks: [...board.value.picks, event.number],
      count: event.count,
    }
    nextPickAt.value = event.next_pick_at

    // Auto-strike if number is on any of my tickets and not yet struck and auto-strike is enabled
    const onMyTicket = myTickets.value.some(t => t.numbers.includes(event.number))
    if (autoStrikeEnabled.value && onMyTicket && !myStruck.value.has(event.number)) {
      autoStrike?.(event.number)
    }
  }

  function onStatusChange(event: GameStatusEvent) {
    status.value = event.status
  }

  function onPrizeClaimed(event: PrizeClaimedEvent) {
    if (prizes.value[event.prize]) {
      prizes.value[event.prize] = { claimed: true, winner_id: event.winner_id }
    }
  }

  function onBogey(event: BogeyEvent) {
    const player = players.value.find(p => p.user_id === event.user_id)
    if (player) {
      player.bogeys = (settings.value.bogey_limit ?? 3) - event.bogeys_remaining
    }
  }

  function onPlayerJoined(event: PlayerJoinedEvent) {
    if (!players.value.find(p => p.user_id === event.user_id)) {
      players.value.push({ user_id: event.user_id, name: event.name, ticket_count: event.ticket_count, prizes_won: [], bogeys: 0 })
    }
  }

  function onPlayerLeft(event: PlayerLeftEvent) {
    players.value = players.value.filter(p => p.user_id !== event.user_id)
  }

  function onStrikeConfirmed(event: StrikeResultEvent) {
    if (event.result === 'ok') {
      myStruck.value = new Set([...myStruck.value, event.number])
    }
  }

  function onTicketCountUpdated(event: TicketCountUpdatedEvent) {
    const player = players.value.find(p => p.user_id === event.user_id)
    if (player) {
      player.ticket_count = event.count
    }
  }

  function onMyTicketsUpdated(event: PlayerTicketsUpdatedEvent) {
    myTickets.value = event.tickets
  }

  function reset() {
    code.value = ''
    hostId.value = null
    status.value = 'lobby'
    board.value = { picks: [], count: 0, finished: false }
    myTickets.value = []
    myStruck.value = new Set()
    players.value = []
    prizes.value = {}
    channelConnected.value = false
    hydrated.value = false
    autoStrikeEnabled.value = false
  }

  return {
    code, name, hostId, status, settings, board, myTickets, myStruck,
    players, prizes, prizeProgress, myPrizeProgress, nextPickAt, channelConnected, hydrated,
    autoStrikeEnabled, hydrate, onPick, onStatusChange, onPrizeClaimed, onBogey,
    onPlayerJoined, onPlayerLeft, onStrikeConfirmed, onTicketCountUpdated,
    onMyTicketsUpdated, reset,
  }
})
