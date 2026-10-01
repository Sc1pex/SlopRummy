<script lang="ts">
  import { onDestroy, untrack } from 'svelte'
  import { device, enterGameMode, exitGameMode, fullscreenSupported, isTouch } from '../lib/device.svelte'
  import { t } from '../lib/i18n.svelte'
  import { navigate } from '../lib/router.svelte'
  import { session } from '../lib/session.svelte'
  import { TableConnection } from '../lib/table.svelte'
  import GameBoard from '../components/game/GameBoard.svelte'
  import WaitingRoom from '../components/WaitingRoom.svelte'

  let { code }: { code: string } = $props()

  // The parent re-creates this component (keyed) when the code changes.
  const conn = new TableConnection(untrack(() => code), session.token!)

  onDestroy(() => {
    conn.leave()
    exitGameMode()
  })

  const playing = $derived(conn.state?.status === 'playing')

  // Leave fullscreen when the match ends and the table goes back to the waiting room.
  let wasPlaying = false
  $effect(() => {
    if (wasPlaying && !playing) exitGameMode()
    wasPlaying = playing
  })

  // On touch devices the game needs fullscreen + landscape. Browsers only grant that
  // from a tap, so when we're not in fullscreen (e.g. after a reload) we ask for one.
  const needsTap = $derived(playing && isTouch && fullscreenSupported && !device.fullscreen)
  const needsRotate = $derived(playing && isTouch && device.portrait && !needsTap)
</script>

{#if conn.status === 'error'}
  <main class="page center">
    <p>{conn.error === 'not_found' ? t('table.not_found') : t('errors.error')}</p>
    <button class="btn" onclick={() => navigate('/')}>← {t('auth.back')}</button>
  </main>
{:else if !conn.state}
  <main class="page center"><p class="muted">{t('table.connecting')}</p></main>
{:else if playing}
  <GameBoard {conn} table={conn.state} />

  {#if needsTap}
    <button class="overlay tap" onclick={enterGameMode}>
      <span class="icon">⤢</span>
      <span>{t('game.tap_to_enter')}</span>
    </button>
  {:else if needsRotate}
    <div class="overlay">
      <span class="icon rotate">📱</span>
      <strong>{t('game.rotate')}</strong>
      <p class="muted">{t('game.rotate_hint')}</p>
    </div>
  {/if}
{:else}
  <WaitingRoom {conn} table={conn.state} />
{/if}

<style>
  .center {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 16px;
    text-align: center;
  }

  .overlay {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    padding: 32px;
    border: 0;
    background: rgb(5 12 10 / 0.94);
    color: var(--text);
    text-align: center;
    font-size: 1.15rem;
  }

  .overlay p {
    max-width: 320px;
    font-size: 0.95rem;
  }

  .icon {
    font-size: 3rem;
    line-height: 1;
  }

  .rotate {
    animation: rotate 2.4s ease-in-out infinite;
  }

  @keyframes rotate {
    0%,
    30% {
      transform: rotate(0);
    }
    60%,
    100% {
      transform: rotate(-90deg);
    }
  }
</style>
