<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
const props = defineProps<{ message: string; variant?: 'success' | 'error' | 'info' }>()
const emit = defineEmits<{ dismiss: [] }>()
let timer: ReturnType<typeof setTimeout>
onMounted(() => { timer = setTimeout(() => emit('dismiss'), 3000) })
onUnmounted(() => clearTimeout(timer))
const colors = { success: 'bg-green-600', error: 'bg-red-600', info: 'bg-zinc-700' }
</script>
<template>
  <div :class="['flex items-center gap-3 rounded-xl px-4 py-3 text-sm text-white shadow-lg', colors[props.variant ?? 'info']]">
    {{ message }}
  </div>
</template>
