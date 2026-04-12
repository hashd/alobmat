export interface User {
  id: string
  name: string
  email: string | null
  phone?: string | null
  avatar_url: string | null
}

export interface Player {
  user_id: string
  name: string
  prizes_won: string[]
  bogeys: number
  ticket_count?: number
}

export interface GameSettings {
  interval: number
  bogey_limit: number
  default_ticket_count: number
  enabled_prizes: string[]
}

// Matches Ticket.to_map/1 — rows is 3x9 grid, null = blank cell
export interface Ticket {
  id: string
  rows: (number | null)[][]
  numbers: number[]
}

// Matches Board.to_map/1
export interface Board {
  picks: number[]
  count: number
  finished: boolean
}

export interface PrizeStatus {
  claimed: boolean
  winner_id: string | null
}

export interface PrizeProgress {
  struck: number
  required: number
}

export type GameStatus = 'lobby' | 'running' | 'paused' | 'finished'
export type Theme = 'light' | 'dark' | 'system'

export interface ChatEntry {
  id: string
  type: 'chat' | 'pick' | 'prize_claimed' | 'bogey' | 'system'
  user_id?: string
  user_name?: string
  text?: string
  number?: number
  prize?: string
  timestamp: string
}

export interface RecentGame {
  code: string
  name: string
  status: string
  host_id: string
  started_at: string | null
  finished_at: string | null
}
