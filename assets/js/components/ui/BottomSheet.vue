<script setup lang="ts">
defineProps<{ open: boolean; title?: string }>()
const emit = defineEmits<{ close: [] }>()
</script>
<template>
  <Teleport to="body">
    <Transition name="sheet">
      <div v-if="open" class="fixed inset-0 z-50 flex items-end">
        <div class="absolute inset-0 bg-black/60" @click="emit('close')" />
        <div class="relative z-10 w-full rounded-t-2xl border-t border-[--border] bg-[--bg] p-6 shadow-2xl">
          <div class="mx-auto mb-4 h-1 w-10 rounded-full bg-[--border]" />
          <h3 v-if="title" class="mb-4 font-semibold">{{ title }}</h3>
          <slot />
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
<style scoped>
.sheet-enter-from, .sheet-leave-to { transform: translateY(100%); }
.sheet-enter-active, .sheet-leave-active { transition: transform 0.3s ease; }
</style>
