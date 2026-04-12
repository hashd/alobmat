import { setActivePinia, createPinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { useGameStore } from '@/stores/game'

beforeEach(() => { setActivePinia(createPinia()) })

describe('gameStore', () => {
  it('onPick appends number to board picks', () => {
    const store = useGameStore()
    store.board = { picks: [], count: 0, finished: false }
    store.onPick({ number: 42, count: 1, next_pick_at: '', server_now: '' })
    expect(store.board.picks).toContain(42)
    expect(store.board.count).toBe(1)
  })

  it('onPick triggers auto-strike for numbers on my ticket', () => {
    const store = useGameStore()
    store.board = { picks: [], count: 0, finished: false }
    store.myTickets = [{ id: 'test-ticket', rows: [], numbers: [42] }]
    store.myStruck = new Set()
    store.autoStrikeEnabled = true
    const struck: number[] = []
    store.onPick({ number: 42, count: 1, next_pick_at: '', server_now: '' }, (n) => struck.push(n))
    expect(struck).toContain(42)
  })

  it('onStatusChange updates status', () => {
    const store = useGameStore()
    store.onStatusChange({ status: 'running' })
    expect(store.status).toBe('running')
  })

  it('onPrizeClaimed marks prize as claimed', () => {
    const store = useGameStore()
    store.prizes = { early_five: { claimed: false, winner_id: null } }
    store.onPrizeClaimed({ prize: 'early_five', winner_id: 'u1', winner_name: 'Alice' })
    expect(store.prizes.early_five.claimed).toBe(true)
    expect(store.prizes.early_five.winner_id).toBe('u1')
  })
})
