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
      'relative inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold transition-all duration-300 focus:outline-none focus:ring-2 focus:ring-[--accent] focus:ring-offset-2 focus:ring-offset-[--bg] disabled:opacity-50 disabled:cursor-not-allowed hover:-translate-y-0.5 shadow-sm overflow-hidden group',
      variant === 'secondary' ? 'border border-[--border] bg-[--surface] text-[--text-primary] hover:bg-[--elevated] hover:border-[--text-secondary] shadow-[0_2px_8px_rgb(0,0,0,0.04)] backdrop-blur-md' :
      variant === 'ghost'     ? 'text-[--text-secondary] hover:text-[--text-primary] hover:bg-[--border] shadow-none hover:shadow-sm' :
      variant === 'danger'    ? 'bg-gradient-to-r from-red-500 to-rose-600 text-white hover:from-red-600 hover:to-rose-700 hover:shadow-[0_4px_12px_rgba(225,29,72,0.3)]' :
                                'bg-gradient-to-r from-[--accent] to-indigo-600 text-white hover:shadow-[0_4px_15px_var(--accent-glow)]'
    ]"
  >
    <!-- Subtle hover gloss for primary button -->
    <div v-if="!variant || variant === 'primary'" class="absolute inset-0 z-0 bg-white opacity-0 transition-opacity duration-300 group-hover:opacity-10 pointer-events-none"></div>

    <span class="relative z-10 flex items-center justify-center gap-2">
      <span v-if="loading" class="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
      <slot />
    </span>
  </button>
</template>
