import type { Board, GameSettings, Player, PrizeStatus, Ticket } from './domain'

// ── Initial join reply ────────────────────────────────────────────────────────
export interface GameJoinReply {
  code: string
  name: string
  status: string
  settings: GameSettings
  board: Board
  players: Player[]
  prizes: Record<string, PrizeStatus>
  prize_progress: Record<string, Record<string, number>>
  my_ticket: Ticket | null
  my_struck: number[]
}

// ── Server → Client events ────────────────────────────────────────────────────
export interface NumberPickedEvent {
  number: number
  count: number
  next_pick_at: string
  server_now: string
}

export interface GameStatusEvent {
  status: string
}

export interface PrizeClaimedEvent {
  prize: string
  winner_id: string
  winner_name: string
}

export interface ClaimRejectionEvent {
  reason: 'bogey' | 'already_claimed' | 'disqualified' | 'invalid'
  bogeys_remaining?: number
}

export interface StrikeResultEvent {
  number: number
  result: 'ok' | 'rejected'
}

export interface BogeyEvent {
  user_id: string
  bogeys_remaining: number
}

export interface ChatEvent {
  id: string
  user_id: string
  user_name: string
  text: string
  timestamp: string
}

export interface ReactionEvent {
  emoji: string
  user_id: string
}

export interface PlayerJoinedEvent {
  user_id: string
  name: string
}

export interface PlayerLeftEvent {
  user_id: string
}

export interface PresenceMeta {
  name: string
  online_at: string
}

export interface PresenceDiff {
  joins: Record<string, PresenceMeta>
  leaves: Record<string, PresenceMeta>
}

// ── Client → Server messages ──────────────────────────────────────────────────
export interface StrikeMessage { number: number }
export interface ClaimMessage { prize: string }
export interface ReactionMessage { emoji: string }
export interface ChatMessage { text: string }
