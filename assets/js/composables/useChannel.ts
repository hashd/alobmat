import { onMounted, onUnmounted } from 'vue'
import { Socket, Channel } from 'phoenix'
import { useAuthStore } from '@/stores/auth'
import { useGameStore } from '@/stores/game'
import { useChatStore } from '@/stores/chat'
import { usePresenceStore } from '@/stores/presence'
import type {
  NumberPickedEvent, GameStatusEvent, PrizeClaimedEvent, ClaimRejectionEvent,
  StrikeResultEvent, BogeyEvent, ChatEvent, ReactionEvent,
  PlayerJoinedEvent, PlayerLeftEvent, PresenceDiff, GameJoinReply,
} from '@/types/channel'

type SocketFactory = (token: string) => Socket

function createSocket(token: string): Socket {
  return new Socket('/socket', { params: { token } })
}

export function useChannel(gameCode: string, socketFactory: SocketFactory = createSocket) {
  const authStore = useAuthStore()
  const gameStore = useGameStore()
  const chatStore = useChatStore()
  const presenceStore = usePresenceStore()

  let socket: Socket | null = null
  let channel: Channel | null = null

  const reactions = { listeners: [] as Array<(r: { emoji: string; user_id: string }) => void> }

  function onReaction(cb: (r: { emoji: string; user_id: string }) => void) {
    reactions.listeners.push(cb)
  }

  function connect() {
    if (!authStore.token) return

    socket = socketFactory(authStore.token)
    socket.connect()

    channel = socket.channel(`game:${gameCode}`)

    channel.join()
      .receive('ok', (reply: GameJoinReply) => {
        gameStore.hydrate(reply)
      })
      .receive('error', (err: { reason: string }) => {
        console.error('Channel join error:', err)
      })

    channel.on('number_picked', (event: NumberPickedEvent) => {
      gameStore.onPick(event, (number) => strike(number))
      chatStore.onPick(event)
    })

    channel.on('status_changed', (event: GameStatusEvent) => {
      gameStore.onStatusChange(event)
    })

    channel.on('prize_claimed', (event: PrizeClaimedEvent) => {
      gameStore.onPrizeClaimed(event)
      chatStore.onPrizeClaimed(event)
    })

    channel.on('claim_rejection', (event: ClaimRejectionEvent) => {
      console.warn('Claim rejected:', event)
    })

    channel.on('strike_result', (event: StrikeResultEvent) => {
      gameStore.onStrikeConfirmed(event)
    })

    channel.on('bogey', (event: BogeyEvent) => {
      gameStore.onBogey(event)
      chatStore.onBogey(event)
    })

    channel.on('chat', (event: ChatEvent) => {
      chatStore.onChat(event)
    })

    channel.on('reaction', (event: ReactionEvent) => {
      reactions.listeners.forEach(cb => cb(event))
    })

    channel.on('player_joined', (event: PlayerJoinedEvent) => {
      gameStore.onPlayerJoined(event)
    })

    channel.on('player_left', (event: PlayerLeftEvent) => {
      gameStore.onPlayerLeft(event)
    })

    channel.on('presence_diff', (diff: PresenceDiff) => {
      presenceStore.syncPresence(diff)
    })

    socket.onOpen(() => {
      gameStore.channelConnected = true
    })

    socket.onClose(() => {
      gameStore.channelConnected = false
    })

    socket.onError(() => {
      gameStore.channelConnected = false
    })
  }

  function strike(number: number) {
    channel?.push('strike', { number })
      .receive('ok', () => {})
  }

  function claim(prize: string) {
    channel?.push('claim', { prize })
  }

  function sendReaction(emoji: string) {
    channel?.push('reaction', { emoji })
  }

  function sendChat(text: string) {
    channel?.push('chat', { text })
  }

  function disconnect() {
    channel?.leave()
    socket?.disconnect()
    gameStore.reset()
    chatStore.reset()
    presenceStore.reset()
    reactions.listeners = []
    channel = null
    socket = null
  }

  onMounted(connect)
  onUnmounted(disconnect)

  return { gameStore, strike, claim, sendReaction, sendChat, onReaction, connect, disconnect }
}
