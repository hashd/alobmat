<script setup lang="ts">
defineProps<{ options: { value: string; label: string }[] }>()
const model = defineModel<string>()
</script>
<template>
  <div class="flex rounded-lg border border-[--border] bg-[--surface] p-0.5">
    <button
      v-for="opt in options"
      :key="opt.value"
      type="button"
      @click="model = opt.value"
      :class="['flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-all',
        model === opt.value ? 'bg-[--accent] text-white' : 'text-[--text-secondary] hover:text-[--text-primary]']"
    >{{ opt.label }}</button>
  </div>
</template>
