<script setup lang="ts">
defineProps<{ label?: string; error?: string; placeholder?: string; type?: string }>()
const model = defineModel<string>()
</script>
<template>
  <div class="flex flex-col gap-1">
    <label v-if="label" class="text-xs font-medium text-[--text-secondary]">{{ label }}</label>
    <input
      v-model="model"
      :type="type ?? 'text'"
      :placeholder="placeholder"
      class="rounded-lg border border-[--border] bg-[--bg] px-3 py-2 text-sm text-[--text-primary] placeholder:text-[--text-secondary] focus:border-[--accent] focus:outline-none"
    />
    <p v-if="error" class="text-xs text-red-500">{{ error }}</p>
  </div>
</template>
