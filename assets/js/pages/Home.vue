<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/api/client'
import type { RecentGame } from '@/types/domain'

const router = useRouter()
const auth = useAuthStore()

const joinCode = ref('')
const recentGames = ref<RecentGame[]>([])

onMounted(async () => {
  try {
    const { games } = await api.games.public()
    recentGames.value = games
  } catch (err) {
    console.warn("Could not load public games", err)
  }

  if (auth.isAuthenticated) {
    try {
      const { games } = await api.games.recent()
      recentGames.value = games
    } catch {}
  }
})

async function joinGame() {
  if (!joinCode.value.trim()) return
  router.push(`/game/${joinCode.value.toUpperCase()}`)
}

async function createGame() {
  router.push('/game/new')
}

async function joinPublic(code: string) {
  router.push(`/game/${code}`)
}
</script>

<template>
  <div class="min-h-screen bg-slate-50 flex flex-col items-center justify-center p-6 relative overflow-hidden font-sans text-slate-900 selection:bg-indigo-500/20">
    <!-- Bright Atmospheric Background with Dynamic Watercolor Orbs -->
    <div class="fixed inset-0 pointer-events-none z-0">
      <div class="absolute -top-[20%] -left-[10%] w-[60vw] h-[60vw] bg-indigo-300/40 rounded-full mix-blend-multiply blur-[140px] animate-[pulse_8s_ease-in-out_infinite]"></div>
      <div class="absolute top-[50%] -right-[20%] w-[70vw] h-[70vw] bg-fuchsia-300/30 rounded-full mix-blend-multiply blur-[150px] animate-[pulse_11s_ease-in-out_infinite_alternate]"></div>
      <div class="absolute top-[20%] left-[50%] w-[40vw] h-[40vw] bg-cyan-200/40 rounded-full mix-blend-multiply blur-[120px] animate-[pulse_14s_ease-in-out_infinite]"></div>
      <!-- Radial vignette for subtle contrast -->
      <div class="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_0%,#f8fafc_100%)] opacity-80"></div>
      <!-- Subtle dot noise texture -->
      <div class="absolute inset-0 bg-[url('data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI0IiBoZWlnaHQ9IjQiPjxyZWN0IHdpZHRoPSI0IiBoZWlnaHQ9IjQiIGZpbGw9IiMwMDAiIGZpbGwtb3BhY2l0eT0iMC4wMiIvPjwvc3ZnPg==')] opacity-40 mix-blend-overlay"></div>
    </div>

    <!-- Main App Container -->
    <div class="relative w-full max-w-[520px] z-10 flex flex-col gap-10 mt-6 animate-[fade-in-up_0.6s_ease-out_forwards]">
      
      <!-- Brand & Hero Header -->
      <div class="text-center space-y-5 flex flex-col items-center">
        <!-- Brand Icon / Logo Mark -->
        <div class="relative group">
          <div class="absolute -inset-2 bg-gradient-to-r from-indigo-400 via-fuchsia-400 to-cyan-400 rounded-full blur-[20px] opacity-20 group-hover:opacity-40 transition-opacity duration-700"></div>
          <div class="relative flex items-center justify-center w-16 h-16 rounded-2xl bg-white/70 border border-white shadow-[0_8px_30px_rgb(0,0,0,0.04)] backdrop-blur-2xl">
            <svg class="w-8 h-8 text-indigo-600 group-hover:scale-110 transition-transform duration-500 ease-out drop-shadow-[0_4px_10px_rgba(79,70,229,0.2)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 2L2 7l10 5 10-5-10-5z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2 17l10 5 10-5M2 12l10 5 10-5" />
            </svg>
          </div>
        </div>
        
        <div class="space-y-1">
          <h1 class="text-6xl md:text-7xl font-extrabold tracking-tighter text-transparent bg-clip-text bg-gradient-to-br from-slate-900 via-indigo-900 to-slate-700 drop-shadow-[0_2px_10px_rgba(0,0,0,0.02)]">
            Mocha
          </h1>
          <p class="text-lg md:text-xl text-slate-600 font-medium tracking-wide">The ultimate modern bingo experience</p>
        </div>
      </div>

      <!-- Core Interaction Area: Join Match -->
      <div class="relative group/card w-full">
        <!-- Deep Ambient Glow behind card -->
        <div class="absolute -inset-[1px] bg-gradient-to-b from-white/60 to-white/0 rounded-[32px] blur-[2px]"></div>
        <div class="absolute inset-0 bg-gradient-to-r from-indigo-400/10 via-fuchsia-400/10 to-cyan-400/10 rounded-[32px] blur-xl opacity-0 group-hover/card:opacity-100 transition duration-700"></div>
        
        <!-- Glassmorphism Card Surface -->
        <div class="relative bg-white/60 backdrop-blur-3xl border border-white rounded-[32px] p-8 md:p-10 shadow-[0_20px_50px_rgba(0,0,0,0.05)] flex flex-col gap-8 overflow-hidden">
          
          <!-- Inner geometric highlight -->
          <div class="absolute top-0 right-0 w-64 h-64 bg-indigo-100/50 rounded-full blur-3xl -translate-y-1/2 translate-x-1/2"></div>

          <div class="flex items-center justify-between pb-2 border-b border-slate-200/50">
            <h2 class="text-2xl font-bold text-slate-800 tracking-tight">Enter Lobby</h2>
            <div class="px-3 py-1.5 rounded-full bg-white/80 border border-emerald-100 text-[10px] font-bold text-emerald-600 uppercase tracking-[0.2em] shadow-[0_4px_15px_rgba(52,211,153,0.1)] flex items-center gap-2">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-[pulse_2s_infinite]"></span>
              Live Server
            </div>
          </div>
          
          <form @submit.prevent="joinGame" class="flex flex-col gap-6 relative z-10">
            <div class="relative group/input">
              <input v-model="joinCode" placeholder="GAME CODE" maxlength="20"
                class="w-full bg-slate-50/50 border border-slate-200/60 rounded-2xl px-6 py-5 md:py-6 text-center text-3xl md:text-4xl text-slate-800 uppercase tracking-[0.3em] font-mono focus:bg-white focus:outline-none focus:ring-4 focus:ring-indigo-500/10 focus:border-indigo-300 transition-all shadow-inner placeholder:text-slate-400" />
            </div>

            <button type="submit" class="relative group/btn w-full rounded-2xl overflow-hidden transition-transform active:scale-[0.98] shadow-[0_8px_25px_rgba(79,70,229,0.25)] hover:shadow-[0_15px_35px_rgba(79,70,229,0.35)]">
              <!-- Vibrant Button Background -->
              <div class="absolute inset-0 bg-gradient-to-r from-indigo-500 via-fuchsia-500 to-indigo-500 bg-[length:200%_auto] animate-[gradient_3s_linear_infinite] transition-opacity"></div>
              <div class="absolute inset-0 opacity-0 group-hover/btn:opacity-20 bg-white transition-opacity duration-300"></div>

              <div class="relative flex items-center justify-center gap-3 w-full h-full rounded-[15px] px-8 py-5">
                <span class="text-white font-bold text-lg tracking-widest uppercase shadow-sm">Launch Session</span>
                <svg class="w-5 h-5 text-white/90 group-hover/btn:translate-x-1 transition-transform duration-300" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M13 7l5 5m0 0l-5 5m5-5H6" />
                </svg>
              </div>
            </button>
          </form>
        </div>
      </div>

      <!-- Navigation Links & Profile -->
      <div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-center gap-4 w-full">
        <template v-if="auth.isAuthenticated">
          <button @click="router.push('/profile')" class="flex-1 flex justify-center items-center gap-3 px-6 py-4 rounded-2xl bg-white/60 hover:bg-white/80 border border-white/60 hover:border-white shadow-[0_8px_20px_rgba(0,0,0,0.02)] hover:shadow-[0_8px_20px_rgba(0,0,0,0.06)] transition-all text-slate-700 hover:text-slate-900 font-semibold backdrop-blur-md group relative overflow-hidden">
            <svg class="w-5 h-5 text-slate-400 group-hover:text-indigo-500 transition-colors" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
            </svg>
            My Profile
          </button>
          <button @click="createGame" class="flex-1 flex justify-center items-center gap-3 px-6 py-4 rounded-2xl bg-indigo-50 hover:bg-indigo-100 border border-indigo-100 hover:border-indigo-200 transition-all text-indigo-700 hover:text-indigo-800 font-semibold backdrop-blur-md group relative overflow-hidden shadow-[0_8px_20px_rgba(79,70,229,0.06)] hover:shadow-[0_8px_25px_rgba(79,70,229,0.1)]">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            Create Match
          </button>
        </template>
        <template v-if="!auth.isAuthenticated">
          <button @click="router.push('/auth')" class="w-full flex justify-center items-center gap-3 px-8 py-4 rounded-xl bg-white/60 hover:bg-white/80 border border-white/60 hover:border-white shadow-[0_8px_20px_rgba(0,0,0,0.02)] transition-all text-slate-700 hover:text-slate-900 font-semibold backdrop-blur-md group relative overflow-hidden">
            <span>Authentication</span>
            <svg class="w-4 h-4 text-slate-400 group-hover:text-indigo-500 transition-colors" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 16l-4-4m0 0l4-4m-4 4h14m-5 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h7a3 3 0 013 3v1" />
            </svg>
          </button>
        </template>
      </div>

      <!-- Recent Games History -->
      <div v-if="recentGames.length" class="mt-2 animate-[fade-in-up_0.6s_ease-out_0.2s_forwards] opacity-0">
        <div class="flex items-center gap-4 mb-5 opacity-80">
          <div class="h-[1px] flex-1 bg-gradient-to-r from-transparent to-slate-200"></div>
          <h3 class="text-[10px] font-bold text-slate-500 uppercase tracking-[0.25em]">Recent Activity</h3>
          <div class="h-[1px] flex-1 bg-gradient-to-l from-transparent to-slate-200"></div>
        </div>
        
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div v-for="(g, idx) in recentGames.slice(0, 4)" :key="g.code" 
            class="group relative overflow-hidden rounded-2xl bg-white/40 hover:bg-white/70 border border-white/60 hover:border-indigo-200 shadow-sm hover:shadow-[0_8px_25px_rgba(0,0,0,0.04)] transition-all duration-300 cursor-pointer backdrop-blur-sm p-4 px-5 flex items-center justify-between"
            @click="router.push(`/game/${g.code}`)">
            
            <div class="relative z-10 flex flex-col gap-1">
              <span class="font-semibold text-sm text-slate-700 group-hover:text-slate-900 transition-colors truncate max-w-[140px]">{{ g.name || 'Unnamed Session' }}</span>
              <span class="text-[11px] text-slate-500 font-mono tracking-wider group-hover:text-indigo-600 transition-colors">{{ g.code }}</span>
            </div>
            
            <div class="relative z-10 w-9 h-9 rounded-full bg-white flex items-center justify-center border border-slate-100 group-hover:border-indigo-100 group-hover:bg-indigo-50 group-hover:shadow-[0_4px_15px_rgba(99,102,241,0.15)] transition-all duration-300">
               <svg class="w-4 h-4 text-slate-400 group-hover:text-indigo-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M9 5l7 7-7 7" />
              </svg>
            </div>
          </div>
        </div>
      </div>

    </div>
  </div>
</template>

<style>
@keyframes gradient {
  0% { background-position: 0% 50%; }
  50% { background-position: 100% 50%; }
  100% { background-position: 0% 50%; }
}
</style>
