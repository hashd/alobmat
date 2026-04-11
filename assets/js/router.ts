import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  { path: '/', component: () => import('@/pages/Home.vue') },
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

  if (!auth.isAuthenticated && auth.token) {
    await auth.loadUser()
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { path: '/auth', query: { redirect: to.fullPath } }
  }
})
