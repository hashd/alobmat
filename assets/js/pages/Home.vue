<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/api/client'
import type { RecentGame } from '@/types/domain'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'

const router = useRouter()
const auth = useAuthStore()

const joinCode = ref('')
const recentGames = ref<RecentGame[]>([])

onMounted(async () => {
  if (auth.isAuthenticated) {
    try {
      const { games } = await api.games.recent()
      recentGames.value = games
    } catch {}
  }
})

async function joinGame() {
  if (!joinCode.value.trim()) return
  router.push(`/game/${joinCode.value.toUpperCase()}`)
}
</script>
<template>
  <div class="mx-auto max-w-lg p-6">
    <div class="mb-8 flex items-center justify-between">
      <h1 class="text-2xl font-bold">Moth</h1>
      <div class="flex gap-2">
        <Button v-if="auth.isAuthenticated" variant="ghost" @click="router.push('/profile')">Profile</Button>
        <Button v-if="auth.isAuthenticated" @click="router.push('/game/new')">New Game</Button>
        <Button v-else @click="router.push('/auth')">Sign in</Button>
      </div>
    </div>

    <Card class="mb-6">
      <h2 class="mb-3 font-semibold">Join a game</h2>
      <form @submit.prevent="joinGame" class="flex gap-2">
        <input v-model="joinCode" placeholder="Game code" maxlength="4"
          class="flex-1 rounded-lg border border-[--border] bg-[--bg] px-3 py-2 text-sm uppercase tracking-widest focus:outline-none focus:border-[--accent]" />
        <Button type="submit">Join</Button>
      </form>
    </Card>

    <div v-if="recentGames.length">
      <h2 class="mb-3 font-semibold text-[--text-secondary]">Recent games</h2>
      <div class="flex flex-col gap-2">
        <Card v-for="g in recentGames" :key="g.code" class="cursor-pointer hover:border-[--accent]" @click="router.push(`/game/${g.code}`)">
          <div class="flex items-center justify-between">
            <span class="font-medium">{{ g.name || g.code }}</span>
            <span class="font-mono text-sm text-[--text-secondary]">{{ g.code }}</span>
          </div>
        </Card>
      </div>
    </div>
  </div>
</template>
