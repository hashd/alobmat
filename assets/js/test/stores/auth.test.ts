import { setActivePinia, createPinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { useAuthStore } from '@/stores/auth'

beforeEach(() => setActivePinia(createPinia()))

describe('authStore', () => {
  it('is unauthenticated by default', () => {
    const store = useAuthStore()
    expect(store.user).toBeNull()
    expect(store.isAuthenticated).toBe(false)
  })

  it('login sets user and persists token', () => {
    const store = useAuthStore()
    store.login({ id: '1', name: 'Alice', email: 'a@b.com', avatar_url: null }, 'tok123')
    expect(store.isAuthenticated).toBe(true)
    expect(localStorage.getItem('auth_token')).toBe('tok123')
  })

  it('logout clears user and token', () => {
    const store = useAuthStore()
    store.login({ id: '1', name: 'Alice', email: 'a@b.com', avatar_url: null }, 'tok123')
    store.logout()
    expect(store.isAuthenticated).toBe(false)
    expect(localStorage.getItem('auth_token')).toBeNull()
  })
})
