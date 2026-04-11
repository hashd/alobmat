<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useThemeStore } from '@/stores/theme'
import { api } from '@/api/client'
import type { RecentGame } from '@/types/domain'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import Avatar from '@/components/ui/Avatar.vue'
import InputField from '@/components/ui/InputField.vue'

const router = useRouter()
const auth = useAuthStore()
const theme = useThemeStore()

const name = ref(auth.user?.name ?? '')
const saving = ref(false)
const recentGames = ref<RecentGame[]>([])

onMounted(async () => {
  try { const { games } = await api.games.recent(); recentGames.value = games } catch {}
})

const saveError = ref('')
async function saveName() {
  saving.value = true
  saveError.value = ''
  try {
    await auth.updateProfile({ name: name.value })
  } catch (e: any) {
    saveError.value = e.message ?? 'Failed to save'
  } finally {
    saving.value = false
  }
}

async function logout() {
  await api.auth.logout().catch(() => {})
  auth.logout()
  router.push('/')
}
</script>
<template>
  <div class="mx-auto max-w-lg p-6">
    <div class="mb-6 flex items-center gap-3">
      <Button variant="ghost" @click="router.back()">←</Button>
      <h1 class="text-xl font-bold">Profile</h1>
    </div>
    <Card class="mb-4">
      <div class="mb-4 flex items-center gap-3">
        <Avatar :name="auth.user!.name" :user-id="auth.user!.id" size="lg" />
        <div>
          <p class="font-semibold">{{ auth.user!.name }}</p>
          <p class="text-sm text-[--text-secondary]">{{ auth.user!.email }}</p>
        </div>
      </div>
      <form @submit.prevent="saveName" class="flex flex-col gap-2">
        <div class="flex gap-2">
          <InputField v-model="name" class="flex-1" placeholder="Your name" />
          <Button type="submit" :loading="saving">Save</Button>
        </div>
        <p v-if="saveError" class="text-xs text-red-500">{{ saveError }}</p>
      </form>
    </Card>
    <Card class="mb-4">
      <div class="flex items-center justify-between">
        <span class="text-sm">Theme</span>
        <div class="flex gap-2">
          <Button v-for="t in ['light','dark','system']" :key="t" variant="ghost" @click="theme.setTheme(t as any)" :class="theme.theme === t ? 'text-[--accent]' : ''">{{ t }}</Button>
        </div>
      </div>
    </Card>
    <div v-if="recentGames.length" class="mb-4">
      <h2 class="mb-2 text-sm font-medium text-[--text-secondary]">Recent games</h2>
      <div class="space-y-2">
        <Card v-for="g in recentGames" :key="g.code" class="cursor-pointer" @click="router.push(`/game/${g.code}`)">
          <div class="flex justify-between text-sm">
            <span>{{ g.name || g.code }}</span>
            <span class="font-mono text-[--text-secondary]">{{ g.code }}</span>
          </div>
        </Card>
      </div>
    </div>
    <Button variant="danger" @click="logout">Sign out</Button>
  </div>
</template>
