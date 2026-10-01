import { api, ApiError, setApiToken } from './api'
import { disconnectSocket } from './socket'
import { load, save } from './storage'
import type { User } from './types'

const TOKEN_KEY = 'remybun.token'

export const session = $state<{ user: User | null; token: string | null; ready: boolean }>({
  user: null,
  token: null,
  ready: false,
})

function setAuth(user: User | null, token: string | null) {
  session.user = user
  session.token = token
  setApiToken(token)
  save(TOKEN_KEY, token)
}

/** Restores the saved session, if its token is still valid. */
export async function initSession() {
  const token = load<string | null>(TOKEN_KEY, null)

  if (token) {
    setApiToken(token)
    try {
      const { user } = await api.me()
      setAuth(user, token)
    } catch (e) {
      // Keep the token on network errors so the player isn't logged out while offline.
      if (e instanceof ApiError && e.status === 401) setAuth(null, null)
      else session.token = token
    }
  }

  session.ready = true
}

export async function playAsGuest() {
  const { user, token } = await api.guest()
  setAuth(user, token)
}

export async function login(email: string, password: string) {
  const { user, token } = await api.login(email, password)
  disconnectSocket()
  setAuth(user, token)
}

/** Registers; a guest is upgraded in place and keeps their token. */
export async function register(params: { username: string; email: string; password: string }) {
  const { user, token } = await api.register(params)
  if (token !== session.token) disconnectSocket()
  setAuth(user, token)
}

export async function logout() {
  try {
    await api.logout()
  } catch {
    // logging out locally is enough
  }
  disconnectSocket()
  setAuth(null, null)
}
