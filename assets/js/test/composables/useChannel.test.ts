import { setActivePinia, createPinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAuthStore } from '@/stores/auth'

function makeMockSocket() {
  const handlers: Record<string, Function> = {}
  const channel = {
    join: () => ({
      receive: (status: string, cb: Function) => {
        if (status === 'ok') cb({
          code: 'TEST', status: 'lobby', name: 'Test Game',
          board: { picks: [], count: 0, finished: false },
          players: [], prizes: {}, prize_progress: {},
          settings: { interval: 30, bogey_limit: 3, enabled_prizes: [] },
          my_ticket: null, my_struck: []
        })
        return { receive: () => ({}) }
      }
    }),
    on: (event: string, cb: Function) => { handlers[event] = cb },
    push: vi.fn().mockReturnValue({ receive: () => ({}) }),
    leave: vi.fn(),
    trigger: (event: string, payload: unknown) => handlers[event]?.(payload),
  }
  return {
    connect: vi.fn(),
    disconnect: vi.fn(),
    onOpen: vi.fn(),
    onClose: vi.fn(),
    onError: vi.fn(),
    channel: vi.fn().mockReturnValue(channel),
    mockChannel: channel,
  }
}

beforeEach(() => { setActivePinia(createPinia()) })

describe('useChannel', () => {
  it('hydrates game store on join', async () => {
    const { useChannel } = await import('@/composables/useChannel')
    const authStore = useAuthStore()
    authStore.token = 'test-token'
    const mockSocket = makeMockSocket()
    const { gameStore, connect } = useChannel('TEST', () => mockSocket as any)
    connect()
    expect(gameStore.code).toBe('TEST')
  })

  it('does not connect when token is null', async () => {
    const { useChannel } = await import('@/composables/useChannel')
    const authStore = useAuthStore()
    authStore.token = null
    const mockSocket = makeMockSocket()
    const { connect } = useChannel('TEST', () => mockSocket as any)
    connect()
    expect(mockSocket.connect).not.toHaveBeenCalled()
  })

  it('resets stores on disconnect', async () => {
    const { useChannel } = await import('@/composables/useChannel')
    const authStore = useAuthStore()
    authStore.token = 'test-token'
    const mockSocket = makeMockSocket()
    const { gameStore, connect, disconnect } = useChannel('TEST', () => mockSocket as any)
    connect()
    expect(gameStore.code).toBe('TEST')
    disconnect()
    expect(gameStore.code).toBe('')
  })

  it('pushes strike message to channel', async () => {
    const { useChannel } = await import('@/composables/useChannel')
    const authStore = useAuthStore()
    authStore.token = 'test-token'
    const mockSocket = makeMockSocket()
    const { strike, connect } = useChannel('TEST', () => mockSocket as any)
    connect()
    strike(42)
    expect(mockSocket.mockChannel.push).toHaveBeenCalledWith('strike', { number: 42 })
  })

  it('dispatches reaction events to listeners', async () => {
    const { useChannel } = await import('@/composables/useChannel')
    const authStore = useAuthStore()
    authStore.token = 'test-token'
    const mockSocket = makeMockSocket()
    const { onReaction, connect } = useChannel('TEST', () => mockSocket as any)
    connect()
    const received: Array<{ emoji: string; user_id: string }> = []
    onReaction((r) => received.push(r))
    mockSocket.mockChannel.trigger('reaction', { emoji: '🎉', user_id: 'user1' })
    expect(received).toHaveLength(1)
    expect(received[0].emoji).toBe('🎉')
  })
})
