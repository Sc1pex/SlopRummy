import type { HistoryGame, Preset, TableSummary, User } from './types'

/** Base URL of the backend. Empty in development: Vite proxies /api and /socket. */
export const API_URL: string = import.meta.env.VITE_API_URL ?? ''

export class ApiError extends Error {
  constructor(
    public status: number,
    public reason: string,
    public fields: Record<string, string[]> = {},
  ) {
    super(reason)
  }
}

let token: string | null = null

export function setApiToken(value: string | null) {
  token = value
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { accept: 'application/json' }
  if (body !== undefined) headers['content-type'] = 'application/json'
  if (token) headers.authorization = `Bearer ${token}`

  let res: Response
  try {
    res = await fetch(`${API_URL}/api${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    throw new ApiError(0, 'network_error')
  }

  if (res.status === 204) return undefined as T
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new ApiError(res.status, data.error ?? (data.errors ? 'validation' : 'error'), data.errors)
  return data as T
}

interface AuthResponse {
  user: User
  token: string
}

export const api = {
  guest: () => request<AuthResponse>('POST', '/guest'),
  register: (params: { username: string; email: string; password: string }) =>
    request<AuthResponse>('POST', '/register', params),
  login: (email: string, password: string) => request<AuthResponse>('POST', '/login', { email, password }),
  logout: () => request<void>('DELETE', '/logout'),
  me: () => request<{ user: User }>('GET', '/me'),
  presets: () => request<{ presets: Record<string, Preset> }>('GET', '/presets'),
  tables: () => request<{ tables: TableSummary[] }>('GET', '/tables'),
  table: (code: string) => request<{ table: { code: string } }>('GET', `/tables/${encodeURIComponent(code)}`),
  createTable: (params: { preset?: string; visibility: 'public' | 'private'; overrides?: Record<string, unknown> }) =>
    request<{ table: { code: string } }>('POST', '/tables', params),
  history: () => request<{ games: HistoryGame[] }>('GET', '/me/games'),
}
