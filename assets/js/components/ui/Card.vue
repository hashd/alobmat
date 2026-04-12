<template>
  <div class="relative overflow-hidden rounded-2xl border border-[--border] bg-[--surface] p-5 shadow-[0_8px_30px_rgb(0,0,0,0.04)] backdrop-blur-xl transition-all duration-300 hover:shadow-[0_8px_30px_rgb(0,0,0,0.08)]">
    <!-- Subtle inset glow for premium feel -->
    <div class="absolute inset-0 z-0 bg-gradient-to-br from-white/10 to-transparent pointer-events-none opacity-50"></div>
    <div class="relative z-10 w-full h-full">
      <slot />
    </div>
  </div>
</template>
