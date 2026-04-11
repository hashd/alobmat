<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/api/client'
import InputField from '@/components/ui/InputField.vue'
import Button from '@/components/ui/Button.vue'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const email = ref('')
const sent = ref(false)
const loading = ref(false)
const error = ref('')

// Handle OAuth callback: /#/auth/callback?token=<t>
onMounted(async () => {
  const token = (route.query.token as string) ?? ''
  if (token) {
    try {
      auth.token = token
      localStorage.setItem('auth_token', token)
      const { user: u } = await api.user.me()
      auth.login(u, token)
      router.replace((route.query.redirect as string) ?? '/')
    } catch {
      error.value = 'Token invalid. Please try again.'
    }
  }
})

async function requestLink() {
  loading.value = true
  error.value = ''
  try {
    await api.auth.requestMagicLink(email.value)
    sent.value = true
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>
<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <div class="w-full max-w-sm">
      <h1 class="mb-8 text-center text-3xl font-bold">Moth</h1>
      <div v-if="sent" class="text-center text-[--text-secondary]">
        Check your email for a sign-in link.
      </div>
      <form v-else @submit.prevent="requestLink" class="flex flex-col gap-4">
        <InputField v-model="email" label="Email" type="email" placeholder="you@example.com" :error="error" />
        <Button type="submit" :loading="loading">Send magic link</Button>
        <a href="/auth/google" class="text-center text-sm text-[--text-secondary] hover:text-[--text-primary]">Continue with Google</a>
      </form>
    </div>
  </div>
</template>
