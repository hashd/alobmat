<script setup lang="ts">
import { computed } from 'vue'
const props = defineProps<{ name: string; userId: string; size?: 'sm' | 'md' | 'lg' }>()
const colors = ['bg-violet-500','bg-blue-500','bg-green-500','bg-yellow-500','bg-pink-500','bg-indigo-500']
const color = computed(() => colors[props.userId.charCodeAt(0) % colors.length])
const initials = computed(() => props.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase())
const sz = computed(() => props.size === 'lg' ? 'h-12 w-12 text-base' : props.size === 'sm' ? 'h-6 w-6 text-xs' : 'h-8 w-8 text-sm')
</script>
<template>
  <div :class="['flex items-center justify-center rounded-full font-bold text-white', color, sz]">{{ initials }}</div>
</template>
