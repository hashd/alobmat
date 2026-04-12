<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/api/client'
import InputField from '@/components/ui/InputField.vue'
import Button from '@/components/ui/Button.vue'
import SegmentedControl from '@/components/ui/SegmentedControl.vue'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const tab = ref<string>('phone')
const tabOptions = [
  { value: 'phone', label: 'Phone' },
  { value: 'email', label: 'Email' },
]

// Email state
const email = ref('')
const emailSent = ref(false)
const emailLoading = ref(false)
const emailError = ref('')

// Phone state
type PhoneStep = 'phone' | 'otp' | 'name'
const phoneStep = ref<PhoneStep>('phone')
const phone = ref('')
const otpCode = ref('')
const displayName = ref('')
const phoneLoading = ref(false)
const phoneError = ref('')
const resendCooldown = ref(0)
let resendTimer: ReturnType<typeof setInterval> | null = null

onUnmounted(() => {
  if (resendTimer) {
    clearInterval(resendTimer)
    resendTimer = null
  }
})

// Handle OAuth callback: /#/auth/callback?token=<t>
onMounted(async () => {
  const token = (route.query.token as string) ?? ''
  if (token) {
    window.history.replaceState({}, '', window.location.pathname)
    try {
      auth.token = token
      localStorage.setItem('auth_token', token)
      const { user: u } = await api.user.me()
      auth.login(u, token)
      router.replace((route.query.redirect as string) ?? '/')
    } catch {
      emailError.value = 'Token invalid. Please try again.'
    }
  }
})

// Email magic link
async function requestLink() {
  emailLoading.value = true
  emailError.value = ''
  try {
    await api.auth.requestMagicLink(email.value)
    emailSent.value = true
  } catch (e: any) {
    emailError.value = e.message
  } finally {
    emailLoading.value = false
  }
}

// Phone OTP
async function requestOtp() {
  phoneLoading.value = true
  phoneError.value = ''
  try {
    await api.auth.requestOtp(phone.value)
    phoneStep.value = 'otp'
    startResendCooldown()
  } catch (e: any) {
    const code = e.body?.error?.code
    if (code === 'invalid_phone') {
      phoneError.value = 'Please enter a valid Indian mobile number.'
    } else if (code === 'rate_limited') {
      phoneError.value = 'Too many attempts. Please wait a few minutes.'
    } else if (code === 'sms_delivery_failed') {
      phoneError.value = 'Could not send SMS. Please try again.'
    } else {
      phoneError.value = e.message
    }
  } finally {
    phoneLoading.value = false
  }
}

async function verifyOtp() {
  phoneLoading.value = true
  phoneError.value = ''
  try {
    const { token, user, needs_name } = await api.auth.verifyOtp(phone.value, otpCode.value)
    if (needs_name) {
      auth.token = token
      localStorage.setItem('auth_token', token)
      auth.login(user, token)
      phoneStep.value = 'name'
    } else {
      auth.login(user, token)
      router.replace((route.query.redirect as string) ?? '/')
    }
  } catch (e: any) {
    const code = e.body?.error?.code
    const remaining = e.body?.error?.attempts_remaining
    if (code === 'too_many_attempts') {
      phoneError.value = 'Too many wrong attempts. Please request a new code.'
    } else if (code === 'invalid_otp' && remaining !== undefined) {
      phoneError.value = `Wrong code. ${remaining} attempt${remaining === 1 ? '' : 's'} left.`
    } else {
      phoneError.value = 'Invalid or expired code.'
    }
  } finally {
    phoneLoading.value = false
  }
}

async function submitName() {
  phoneLoading.value = true
  phoneError.value = ''
  try {
    await auth.updateProfile({ name: displayName.value })
    router.replace((route.query.redirect as string) ?? '/')
  } catch (e: any) {
    phoneError.value = e.message
  } finally {
    phoneLoading.value = false
  }
}

function startResendCooldown() {
  resendCooldown.value = 30
  if (resendTimer) clearInterval(resendTimer)
  resendTimer = setInterval(() => {
    resendCooldown.value--
    if (resendCooldown.value <= 0 && resendTimer) {
      clearInterval(resendTimer)
      resendTimer = null
    }
  }, 1000)
}

async function resendOtp() {
  phoneError.value = ''
  try {
    await api.auth.requestOtp(phone.value)
    otpCode.value = ''
    startResendCooldown()
  } catch (e: any) {
    const code = e.body?.error?.code
    if (code === 'rate_limited') {
      phoneError.value = 'Too many attempts. Please wait a few minutes.'
    } else {
      phoneError.value = 'Could not resend. Please try again.'
    }
  }
}

function maskedPhone() {
  if (phone.value.length >= 10) {
    const digits = phone.value.replace(/\D/g, '').slice(-10)
    return `+91 ${digits.slice(0, 5)} ${digits.slice(5)}`
  }
  return phone.value
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <div class="w-full max-w-sm">
      <h1 class="mb-8 text-center text-3xl font-bold">Moth</h1>

      <SegmentedControl v-model="tab" :options="tabOptions" class="mb-6" />

      <!-- Phone tab -->
      <template v-if="tab === 'phone'">
        <!-- Step 1: Phone entry -->
        <form v-if="phoneStep === 'phone'" @submit.prevent="requestOtp" class="flex flex-col gap-4">
          <InputField
            v-model="phone"
            label="Mobile number"
            type="tel"
            inputmode="numeric"
            placeholder="98765 43210"
            :error="phoneError"
          />
          <Button type="submit" :loading="phoneLoading">Send OTP</Button>
        </form>

        <!-- Step 2: OTP entry -->
        <form v-else-if="phoneStep === 'otp'" @submit.prevent="verifyOtp" class="flex flex-col gap-4">
          <p class="text-sm text-[--text-secondary]">Enter the 6-digit code sent to {{ maskedPhone() }}</p>
          <InputField
            v-model="otpCode"
            label="OTP Code"
            type="text"
            inputmode="numeric"
            maxlength="6"
            autocomplete="one-time-code"
            placeholder="123456"
            :error="phoneError"
          />
          <Button type="submit" :loading="phoneLoading">Verify</Button>
          <button
            type="button"
            :disabled="resendCooldown > 0"
            @click="resendOtp"
            class="text-center text-sm text-[--text-secondary] hover:text-[--text-primary] disabled:opacity-50"
          >
            {{ resendCooldown > 0 ? `Resend code in ${resendCooldown}s` : 'Resend code' }}
          </button>
        </form>

        <!-- Step 3: Name entry -->
        <form v-else-if="phoneStep === 'name'" @submit.prevent="submitName" class="flex flex-col gap-4">
          <p class="text-sm text-[--text-secondary]">What should we call you?</p>
          <InputField
            v-model="displayName"
            label="Display name"
            type="text"
            placeholder="Your name"
            :error="phoneError"
          />
          <Button type="submit" :loading="phoneLoading" :disabled="displayName.trim().length < 2">
            Start playing
          </Button>
        </form>
      </template>

      <!-- Email tab -->
      <template v-else>
        <div v-if="emailSent" class="text-center text-[--text-secondary]">
          Check your email for a sign-in link.
        </div>
        <form v-else @submit.prevent="requestLink" class="flex flex-col gap-4">
          <InputField v-model="email" label="Email" type="email" placeholder="you@example.com" :error="emailError" />
          <Button type="submit" :loading="emailLoading">Send magic link</Button>
          <a href="/auth/google" class="text-center text-sm text-[--text-secondary] hover:text-[--text-primary]">Continue with Google</a>
        </form>
      </template>
    </div>
  </div>
</template>
