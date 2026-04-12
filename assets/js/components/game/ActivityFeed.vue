<script setup lang="ts">
import { computed, ref } from 'vue'
import { useAutoScroll } from '@/composables/useAutoScroll'
import { useChatStore } from '@/stores/chat'
import { useAuthStore } from '@/stores/auth'
import type { ChatEntry } from '@/types/domain'

const chat = useChatStore()
const auth = useAuthStore()
const emit = defineEmits<{ 
  sendChat: [text: string],
  close: []
}>()

const filtered = computed<ChatEntry[]>(() =>
  chat.filter === 'all' ? chat.entries :
  chat.filter === 'chat' ? chat.entries.filter(e => e.type === 'chat') :
  chat.entries.filter(e => e.type !== 'chat')
)

const { containerRef } = useAutoScroll(() => filtered.value.length)
const draft = ref('')

const filterOptions = [
  { value: 'all', label: 'All' },
  { value: 'chat', label: 'Chat' },
  { value: 'events', label: 'Events' },
]
</script>
<template>
  <div class="flex flex-col h-full relative p-4">
    <!-- Tabs -->
    <div class="flex items-center bg-[--surface] p-1 rounded-xl border border-[--border] mb-4 shadow-sm">
      <div class="flex flex-1">
        <button 
          v-for="opt in filterOptions" 
          :key="opt.value"
          @click="chat.filter = opt.value as any"
          class="flex-1 py-1.5 text-[10px] font-black uppercase tracking-widest transition-all duration-300 rounded-lg"
          :class="[
            chat.filter === opt.value 
              ? 'bg-indigo-500 text-white shadow-sm' 
              : 'text-[--text-muted] hover:text-[--text-primary] hover:bg-[--elevated]'
          ]"
        >
          {{ opt.label }}
        </button>
      </div>
      <div class="w-[1px] h-4 bg-[--border] mx-1"></div>
      <button 
        @click="emit('close')" 
        class="w-8 h-8 rounded-lg flex items-center justify-center text-[--text-muted] hover:text-[--text-primary] hover:bg-[--elevated] transition-colors"
      >
        ✕
      </button>
    </div>

    <!-- Scrollable Feed -->
    <div ref="containerRef" class="flex-1 overflow-y-auto space-y-3 min-h-0 pr-2 pb-2 mr-[-8px] scrollbar-thin scrollbar-thumb-indigo-500/20 scrollbar-track-transparent">
      <div v-for="entry in filtered" :key="entry.id" class="text-sm flex flex-col animate-fade-in-up">
        
        <!-- Chat Message -->
        <div v-if="entry.type === 'chat'" class="flex gap-2.5 max-w-[95%] w-full my-1.5" :class="[entry.user_id === auth.user?.id ? 'self-end flex-row-reverse' : 'self-start']">
          <Avatar :name="entry.user_name ?? '?'" :user-id="entry.user_id ?? '?'" size="sm" class="flex-shrink-0 mt-1 shadow-sm border border-white/10" />
          <div class="flex flex-col max-w-[85%]" :class="[entry.user_id === auth.user?.id ? 'items-end' : 'items-start']">
            <span class="text-[9px] uppercase tracking-wider font-bold text-[--text-muted] mb-1 px-1">
              {{ entry.user_name }} • {{ new Date(entry.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }}
            </span>
            <div class="rounded-2xl px-4 py-2.5 shadow-sm text-sm" 
                 :class="[
                   entry.user_id === auth.user?.id 
                     ? 'bg-gradient-to-br from-indigo-500 to-purple-600 text-white rounded-tr-sm shadow-indigo-500/20 shadow-md' 
                     : 'bg-[--surface]/90 backdrop-blur-md border border-[--border] text-[--text-primary] rounded-tl-sm'
                 ]">
              {{ entry.text }}
            </div>
          </div>
        </div>

        <!-- Pick Event -->
        <div v-else-if="entry.type === 'pick'" class="flex items-center gap-2 self-center my-2 opacity-80">
          <div class="h-px w-8 bg-gradient-to-r from-transparent to-[--border]"></div>
          <span class="px-3 py-1 rounded-full bg-indigo-500/10 text-indigo-500 border border-indigo-500/20 text-xs font-bold shadow-sm inline-flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-indigo-400 animate-pulse"></span> Picked: {{ entry.number }}
          </span>
          <div class="h-px w-8 bg-gradient-to-l from-transparent to-[--border]"></div>
        </div>

        <!-- Prize Event -->
        <div v-else-if="entry.type === 'prize_claimed'" class="self-center my-2 px-4 py-2 bg-gradient-to-r from-yellow-500/10 via-yellow-400/10 to-yellow-500/10 rounded-xl border border-yellow-500/30 text-yellow-600 dark:text-yellow-400 text-xs font-bold text-center shadow-[0_0_15px_rgba(234,179,8,0.1)]">
          <span class="text-lg block mb-1">🏆</span>
          {{ entry.user_name }} won {{ entry.prize?.replace(/_/g, ' ') }}!
        </div>

        <!-- Bogey Event -->
        <div v-else-if="entry.type === 'bogey'" class="self-center my-2 px-3 py-1 bg-red-500/10 border border-red-500/30 rounded-full text-red-500 text-xs font-bold inline-flex items-center gap-2 shadow-sm">
          <span>❌</span> Bogey!
        </div>

        <!-- System/Misc Event -->
        <div v-else class="text-[--text-secondary] text-xs italic text-center my-1">
          {{ entry.text }}
        </div>
      </div>
      
      <div v-if="filtered.length === 0" class="flex flex-col items-center justify-center h-full text-[--text-muted] opacity-60">
        <span class="text-3xl mb-2">💬</span>
        <span class="text-sm font-medium">No activity yet</span>
      </div>
    </div>

    <!-- Input Form -->
    <form @submit.prevent="draft && emit('sendChat', draft); draft = ''" class="mt-4 pt-3 border-t border-[--border]/50 flex gap-2 relative">
      <input v-model="draft" placeholder="Send a message..." class="flex-1 rounded-xl border border-[--border] bg-[--surface] px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 transition-all shadow-inner placeholder:text-[--text-muted]" />
      <button v-show="draft.trim()" type="submit" class="absolute right-1 top-[13px] bottom-[1px] rounded-lg bg-[--accent] px-3 font-bold text-white text-xs hover:scale-105 transition-transform hover:shadow-[0_0_10px_rgba(99,102,241,0.4)] my-1 mr-1">
        Send
      </button>
    </form>
  </div>
</template>
