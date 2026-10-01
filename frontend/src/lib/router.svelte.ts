// Minimal history-API router. Routes: /, /login, /history, /t/:code

export type Route =
  | { name: 'lobby' }
  | { name: 'login'; next?: string }
  | { name: 'history' }
  | { name: 'table'; code: string }

function parse(path: string, search: string): Route {
  const table = path.match(/^\/t\/([A-Za-z0-9]+)\/?$/)
  if (table) return { name: 'table', code: table[1].toUpperCase() }
  if (path === '/login') return { name: 'login', next: new URLSearchParams(search).get('next') ?? undefined }
  if (path === '/history') return { name: 'history' }
  return { name: 'lobby' }
}

export const router = $state<{ route: Route }>({ route: parse(location.pathname, location.search) })

export function navigate(path: string, { replace = false } = {}) {
  if (replace) history.replaceState(null, '', path)
  else history.pushState(null, '', path)
  router.route = parse(location.pathname, location.search)
  window.scrollTo(0, 0)
}

window.addEventListener('popstate', () => {
  router.route = parse(location.pathname, location.search)
})

export const tableUrl = (code: string) => `${location.origin}/t/${code}`
