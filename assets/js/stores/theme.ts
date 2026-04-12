import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Theme } from '@/types/domain'

export const useThemeStore = defineStore('theme', () => {
  const stored = (localStorage.getItem('theme') as Theme) ?? 'system'
  const theme = ref<Theme>(stored)

  function applyTheme(t: Theme) {
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    const dark = t === 'dark' || (t === 'system' && prefersDark)
    document.documentElement.classList.toggle('dark', dark)
  }

  function setTheme(t: Theme) {
    theme.value = t
    localStorage.setItem('theme', t)
    applyTheme(t)
  }

  function toggle() {
    setTheme(theme.value === 'dark' ? 'light' : 'dark')
  }

  // Apply on init
  applyTheme(stored)

  return { theme, setTheme, toggle }
})
