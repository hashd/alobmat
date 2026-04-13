import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  { path: '/', component: () => import('@/pages/Home.vue'), meta: { requiresAuth: true } },
  { path: '/auth', component: () => import('@/pages/Auth.vue') },
  { path: '/auth/callback', component: () => import('@/pages/Auth.vue') },
  {
    path: '/profile',
    component: () => import('@/pages/Profile.vue'),
    meta: { requiresAuth: true },
  },
  {
    path: '/game/new',
    component: () => import('@/pages/NewGame.vue'),
    meta: { requiresAuth: true },
  },
  {
    path: '/game/:code',
    component: () => import('@/pages/GamePlay.vue'),
    meta: { requiresAuth: true },
  },
  {
    path: '/game/:code/host',
    component: () => import('@/pages/HostDashboard.vue'),
    meta: { requiresAuth: true, requiresHost: true },
  },
]

export const router = createRouter({
  history: createWebHashHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (!auth.isAuthenticated) {
    await auth.loadUser()
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { path: '/auth', query: { redirect: to.fullPath } }
  }

  // Enforce host-only routes — redirect non-hosts to the player view
  if (to.meta.requiresHost && auth.user) {
    const code = to.params.code as string
    if (code) {
      try {
        const res = await fetch(`/api/games/${code}`, {
          headers: { Authorization: `Bearer ${auth.token}` },
        })
        if (res.ok) {
          const { game } = await res.json()
          if (game.host_id !== auth.user.id) {
            return { path: `/game/${code}` }
          }
        }
      } catch {
        // If we can't verify, let the page handle it
      }
    }
  }
})
