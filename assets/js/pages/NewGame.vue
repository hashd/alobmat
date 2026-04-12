<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/api/client'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import InputField from '@/components/ui/InputField.vue'

const router = useRouter()

const name = ref('')
const interval = ref(30)
const bogeyLimit = ref(3)
const enabledPrizes = ref(['early_five', 'top_line', 'middle_line', 'bottom_line', 'full_house'])
const defaultTicketCount = ref(1)
const visibility = ref<'public' | 'private'>('public')
const joinSecret = ref('')
const loading = ref(false)
const error = ref('')

const prizeOptions = [
  { value: 'early_five', label: 'Early Five' },
  { value: 'top_line', label: 'Top Line' },
  { value: 'middle_line', label: 'Middle Line' },
  { value: 'bottom_line', label: 'Bottom Line' },
  { value: 'full_house', label: 'Full House' },
]

function togglePrize(p: string) {
  enabledPrizes.value = enabledPrizes.value.includes(p)
    ? enabledPrizes.value.filter(x => x !== p)
    : [...enabledPrizes.value, p]
}

async function create() {
  loading.value = true
  error.value = ''
  try {
    const { code } = await api.games.create({
      name: name.value || 'Tambola',
      interval: interval.value,
      bogey_limit: bogeyLimit.value,
      default_ticket_count: defaultTicketCount.value,
      enabled_prizes: enabledPrizes.value,
      visibility: visibility.value,
      join_secret: visibility.value === 'private' ? joinSecret.value : undefined,
    })
    router.push(`/game/${code}/host`)
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>
<template>
  <div class="mx-auto max-w-lg p-6">
    <div class="mb-6 flex items-center gap-3">
      <Button variant="ghost" @click="router.back()">←</Button>
      <h1 class="text-xl font-bold">New Game</h1>
    </div>
    <form @submit.prevent="create" class="flex flex-col gap-4">
      <InputField v-model="name" label="Game name" placeholder="Tambola Night" />

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Visibility</h3>
        <div class="flex gap-2 mb-4">
          <Button type="button" :variant="visibility === 'public' ? 'primary' : 'secondary'" @click="visibility = 'public'" class="flex-1">Public</Button>
          <Button type="button" :variant="visibility === 'private' ? 'primary' : 'secondary'" @click="visibility = 'private'" class="flex-1">Private</Button>
        </div>
        <InputField v-if="visibility === 'private'" v-model="joinSecret" label="Join Secret" placeholder="Enter a secret code" type="password" />
      </Card>

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Pick interval</h3>
        <div class="flex gap-2">
          <Button v-for="s in [5,15,30,60]" :key="s" type="button" :variant="interval === s ? 'primary' : 'secondary'" @click="interval = s">{{ s }}s</Button>
        </div>
      </Card>

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Bogey limit</h3>
        <div class="flex gap-2">
          <Button v-for="b in [1,2,3,5]" :key="b" type="button" :variant="bogeyLimit === b ? 'primary' : 'secondary'" @click="bogeyLimit = b">{{ b }}</Button>
        </div>
      </Card>

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Tickets per player</h3>
        <div class="flex gap-2">
          <Button v-for="n in [1,2,3,4,5,6]" :key="n" type="button" :variant="defaultTicketCount === n ? 'primary' : 'secondary'" @click="defaultTicketCount = n">{{ n }}</Button>
        </div>
      </Card>

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Prizes</h3>
        <div class="flex flex-wrap gap-2">
          <button v-for="p in prizeOptions" :key="p.value" type="button"
            @click="togglePrize(p.value)"
            :class="['rounded-full border px-3 py-1 text-sm transition-all', enabledPrizes.includes(p.value) ? 'border-[--accent] bg-[--accent]/10 text-[--accent]' : 'border-[--border] text-[--text-secondary]']"
          >{{ p.label }}</button>
        </div>
      </Card>

      <p v-if="error" class="text-sm text-red-500">{{ error }}</p>
      <Button type="submit" :loading="loading">Create game</Button>
    </form>
  </div>
</template>
