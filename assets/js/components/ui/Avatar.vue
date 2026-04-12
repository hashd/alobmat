<script setup lang="ts">
import { computed } from 'vue'
const props = defineProps<{ name: string; userId: string; size?: 'sm' | 'md' | 'lg' }>()

const gradients = [
  'bg-gradient-to-br from-violet-500 to-fuchsia-600',
  'bg-gradient-to-br from-blue-500 to-cyan-500',
  'bg-gradient-to-br from-emerald-400 to-teal-600',
  'bg-gradient-to-br from-amber-400 to-orange-500',
  'bg-gradient-to-br from-pink-500 to-rose-600',
  'bg-gradient-to-br from-indigo-500 to-purple-600'
]
const gradient = computed(() => gradients[props.userId.charCodeAt(0) % gradients.length])
const initials = computed(() => props.name ? props.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase() : '?')
const sz = computed(() => props.size === 'lg' ? 'h-12 w-12 text-base shadow-md' : props.size === 'sm' ? 'h-7 w-7 text-[10px]' : 'h-9 w-9 text-xs shadow-sm')
</script>
<template>
  <div :class="['flex items-center justify-center rounded-full font-bold text-white shadow-inner border border-white/20', gradient, sz]">
    {{ initials }}
  </div>
</template>
