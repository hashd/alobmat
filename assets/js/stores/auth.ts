import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { User } from '@/types/domain'
import { api } from '@/api/client'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const token = ref<string | null>(localStorage.getItem('auth_token'))

  const isAuthenticated = computed(() => user.value !== null && token.value !== null)

  function login(u: User, t: string) {
    user.value = u
    token.value = t
    localStorage.setItem('auth_token', t)
  }

  function logout() {
    user.value = null
    token.value = null
    localStorage.removeItem('auth_token')
  }

  async function loadUser() {
    if (!token.value) return
    try {
      const { user: u } = await api.user.me()
      user.value = u
    } catch {
      logout()
    }
  }

  async function updateProfile(attrs: Partial<User>) {
    const { user: u } = await api.user.update(attrs)
    user.value = u
  }

  return { user, token, isAuthenticated, login, logout, loadUser, updateProfile }
})
