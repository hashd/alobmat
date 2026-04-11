import type { User, RecentGame } from '@/types/domain'

const BASE = '/api'

function authHeader(): Record<string, string> {
  const token = localStorage.getItem('auth_token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...authHeader() },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }))
    throw Object.assign(new Error(err.error ?? res.statusText), { status: res.status, body: err })
  }
  return res.json()
}

export const api = {
  auth: {
    requestMagicLink: (email: string) =>
      request<void>('POST', '/auth/magic', { email }),
    verifyMagicLink: (token: string) =>
      request<{ token: string; user: User }>('GET', `/auth/magic/verify?token=${token}`),
    refresh: () =>
      request<{ token: string }>('POST', '/auth/refresh'),
    logout: () =>
      request<void>('DELETE', '/auth/session'),
    devLogin: () =>
      request<{ token: string; user: User }>('POST', '/auth/dev'),
  },
  user: {
    me: () => request<{ user: User }>('GET', '/user/me'),
    update: (attrs: Partial<User>) => request<{ user: User }>('PATCH', '/user/me', attrs),
  },
  games: {
    recent: () => request<{ games: RecentGame[] }>('GET', '/games'),
    get: (code: string) => request<{ game: unknown }>('GET', `/games/${code}`),
    create: (attrs: { name: string; interval: number; bogey_limit: number; enabled_prizes: string[] }) =>
      request<{ code: string }>('POST', '/games', attrs),
    join: (code: string) => request<{ ticket: unknown }>('POST', `/games/${code}/join`),
    start: (code: string) => request<void>('POST', `/games/${code}/start`),
    pause: (code: string) => request<void>('POST', `/games/${code}/pause`),
    resume: (code: string) => request<void>('POST', `/games/${code}/resume`),
    end: (code: string) => request<void>('POST', `/games/${code}/end`),
    clone: (code: string) => request<{ code: string }>('POST', `/games/${code}/clone`),
  },
}
