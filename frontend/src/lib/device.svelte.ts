// Device capabilities: touch, fullscreen, orientation lock, PWA install.
//
// Browsers only allow fullscreen and orientation lock from a user gesture, so
// enterGameMode() must be called from a click/tap handler. iPhone Safari supports
// neither; there we rely on the "rotate your phone" overlay and on installing the PWA.

type FullscreenDoc = Document & {
  webkitFullscreenEnabled?: boolean
  webkitFullscreenElement?: Element | null
  webkitExitFullscreen?: () => Promise<void>
}
type FullscreenEl = HTMLElement & { webkitRequestFullscreen?: () => Promise<void> }
type LockableOrientation = ScreenOrientation & { lock?: (o: string) => Promise<void> }
interface InstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

const doc = document as FullscreenDoc
const mq = (q: string) => window.matchMedia(q)

export const isTouch = mq('(pointer: coarse)').matches
export const isIOS =
  /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
export const isStandalone =
  mq('(display-mode: standalone)').matches ||
  mq('(display-mode: fullscreen)').matches ||
  (navigator as Navigator & { standalone?: boolean }).standalone === true
export const fullscreenSupported = !!(doc.fullscreenEnabled || doc.webkitFullscreenEnabled)

const fullscreenElement = () => doc.fullscreenElement ?? doc.webkitFullscreenElement ?? null

export const device = $state({
  portrait: mq('(orientation: portrait)').matches,
  fullscreen: !!fullscreenElement(),
  canInstall: false,
})

mq('(orientation: portrait)').addEventListener('change', (e) => (device.portrait = e.matches))
for (const event of ['fullscreenchange', 'webkitfullscreenchange']) {
  document.addEventListener(event, () => (device.fullscreen = !!fullscreenElement()))
}

let installPrompt: InstallPromptEvent | null = null
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault()
  installPrompt = e as InstallPromptEvent
  device.canInstall = true
})
window.addEventListener('appinstalled', () => (device.canInstall = false))

export async function promptInstall() {
  if (!installPrompt) return
  await installPrompt.prompt()
  await installPrompt.userChoice
  installPrompt = null
  device.canInstall = false
}

/** Fullscreen + landscape lock on touch devices. Call from a tap/click handler. */
export async function enterGameMode() {
  if (!isTouch) return
  try {
    if (fullscreenSupported && !fullscreenElement()) {
      const el = document.documentElement as FullscreenEl
      if (el.requestFullscreen) await el.requestFullscreen({ navigationUI: 'hide' })
      else await el.webkitRequestFullscreen?.()
    }
  } catch {
    // denied or unsupported
  }
  try {
    await (screen.orientation as LockableOrientation | undefined)?.lock?.('landscape')
  } catch {
    // not supported (iOS) or not allowed outside fullscreen
  }
}

export async function exitGameMode() {
  try {
    screen.orientation?.unlock?.()
  } catch {
    // ignore
  }
  try {
    if (fullscreenElement()) {
      if (doc.exitFullscreen) await doc.exitFullscreen()
      else await doc.webkitExitFullscreen?.()
    }
  } catch {
    // ignore
  }
}

/** Optional fullscreen for desktop players. */
export async function toggleFullscreen() {
  if (fullscreenElement()) await exitGameMode()
  else if (fullscreenSupported) await document.documentElement.requestFullscreen().catch(() => {})
}
