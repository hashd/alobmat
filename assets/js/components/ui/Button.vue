<script setup lang="ts">
defineProps<{
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  loading?: boolean
  disabled?: boolean
  type?: 'button' | 'submit'
}>()
</script>

<template>
  <button
    :type="type ?? 'button'"
    :disabled="disabled || loading"
    :class="[
      'inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-all focus:outline-none disabled:opacity-50',
      variant === 'secondary' ? 'border border-[--border] bg-transparent text-[--text-primary] hover:bg-[--surface]' :
      variant === 'ghost'     ? 'text-[--text-secondary] hover:text-[--text-primary] hover:bg-[--surface]' :
      variant === 'danger'    ? 'bg-red-600 text-white hover:bg-red-700' :
                                'bg-[--accent] text-white hover:opacity-90'
    ]"
  >
    <span v-if="loading" class="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
    <slot />
  </button>
</template>
