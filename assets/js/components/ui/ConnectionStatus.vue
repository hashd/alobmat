<script setup lang="ts">
defineProps<{ connected: boolean }>()
</script>
<template>
  <Transition name="fade">
    <div v-if="!connected" class="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-2 rounded-full bg-zinc-800 px-4 py-2 text-sm text-white shadow-lg">
      <span class="h-2 w-2 animate-pulse rounded-full bg-yellow-400" />
      Reconnecting…
    </div>
  </Transition>
</template>
<style scoped>
.fade-enter-from, .fade-leave-to { opacity: 0; }
.fade-enter-active, .fade-leave-active { transition: opacity 0.2s; }
</style>
