<script lang="ts">
  import { enterGameMode, exitGameMode } from '../lib/device.svelte'
  import { errorText, t } from '../lib/i18n.svelte'
  import { navigate, tableUrl } from '../lib/router.svelte'
  import { session } from '../lib/session.svelte'
  import type { TableConnection } from '../lib/table.svelte'
  import { toast } from '../lib/toasts.svelte'
  import type { TableState } from '../lib/types'
  import ChatPanel from './ChatPanel.svelte'
  import MatchResults from './MatchResults.svelte'
  import RulesEditor from './RulesEditor.svelte'
  import RulesSummary from './RulesSummary.svelte'
  import TopBar from './TopBar.svelte'

  let { conn, table }: { conn: TableConnection; table: TableState } = $props()

  const me = $derived(session.user!.id)
  const mySeat = $derived(table.seats.find((s) => s.user?.id === me))
  const isHost = $derived(table.host_id === me)
  const seated = $derived(table.seats.filter((s) => s.user))
  const allReady = $derived(seated.every((s) => s.ready || s.user!.id === me))
  const canStart = $derived(seated.length >= table.rules.min_players && allReady)

  let editingRules = $state(false)
  let copied = $state(false)

  async function act(event: string, payload: Record<string, unknown> = {}) {
    try {
      await conn.push(event, payload)
    } catch (reason) {
      toast(errorText(String(reason)), 'error')
    }
  }

  function toggleReady() {
    const ready = !mySeat?.ready
    // Fullscreen/landscape must be requested inside the tap, before the game starts.
    if (ready) enterGameMode()
    else exitGameMode()
    act('ready', { ready })
  }

  function start() {
    enterGameMode()
    act('start')
  }

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(tableUrl(table.code))
      copied = true
      setTimeout(() => (copied = false), 1500)
    } catch {
      toast(tableUrl(table.code))
    }
  }

  function share() {
    navigator.share({ title: 'Remybun', text: t('table.invite'), url: tableUrl(table.code) }).catch(() => {})
  }
</script>

<main class="page">
  <TopBar>
    <button class="btn btn-ghost btn-sm" onclick={() => navigate('/')}>{t('table.leave')}</button>
  </TopBar>

  {#if table.last_result}
    <MatchResults result={table.last_result} />
  {/if}

  <section class="panel invite">
    <div>
      <div class="muted small">{t('table.invite')}</div>
      <div class="code">{table.code}</div>
    </div>
    <div class="row">
      <button class="btn btn-sm" onclick={copyLink}>{copied ? t('table.copied') : t('table.copy')}</button>
      {#if 'share' in navigator}
        <button class="btn btn-sm" onclick={share}>{t('table.share')}</button>
      {/if}
    </div>
  </section>

  <section class="seats felt">
    {#each table.seats as seat (seat.seat)}
      <div class="seat" class:mine={seat.user?.id === me}>
        {#if seat.user}
          <div class="avatar" class:offline={!seat.user.connected}>{seat.user.username.slice(0, 1).toUpperCase()}</div>
          <div class="name">{seat.user.username}</div>
          <div class="badges">
            {#if seat.user.id === table.host_id}<span class="badge badge-accent">{t('table.host')}</span>{/if}
            {#if seat.ready}<span class="badge badge-ok">{t('table.is_ready')}</span>{/if}
            {#if !seat.user.connected}<span class="badge">{t('game.offline')}</span>{/if}
          </div>
          {#if seat.user.id === me}
            <button class="btn btn-ghost btn-sm" onclick={() => act('stand')}>{t('table.stand')}</button>
          {/if}
        {:else}
          <div class="avatar empty">+</div>
          <div class="name muted">{t('table.empty_seat')}</div>
          <button class="btn btn-sm" onclick={() => act('sit', { seat: seat.seat })}>{t('table.sit')}</button>
        {/if}
      </div>
    {/each}
  </section>

  <section class="actions">
    {#if mySeat}
      {#if isHost}
        <button class="btn btn-primary big" disabled={!canStart} onclick={start}>{t('table.start')}</button>
      {:else}
        <button class="btn big" class:btn-primary={!mySeat.ready} onclick={toggleReady}>
          {mySeat.ready ? t('table.not_ready') : t('table.ready')}
        </button>
      {/if}
    {/if}
    <p class="muted small">
      {#if seated.length < table.rules.min_players}
        {t('table.need_players', { n: table.rules.min_players })}
      {:else if !isHost}
        {t('table.waiting_host')}
      {/if}
    </p>
  </section>

  <section class="panel">
    <div class="panel-head">
      <h2>{t('table.rules')}</h2>
      {#if isHost && !editingRules}
        <button class="btn btn-ghost btn-sm" onclick={() => (editingRules = true)}>{t('table.edit_rules')}</button>
      {/if}
    </div>
    {#if editingRules}
      <RulesEditor
        rules={table.rules}
        preset={table.preset}
        onsave={async (preset, overrides) => {
          await act('update_rules', { preset, overrides })
          editingRules = false
        }}
        oncancel={() => (editingRules = false)}
      />
    {:else}
      <RulesSummary rules={table.rules} />
    {/if}
  </section>

  <section class="panel chat">
    <h2>{t('table.chat')}</h2>
    <ChatPanel {conn} />
  </section>
</main>

<style>
  main {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .small {
    font-size: 0.85rem;
  }

  .invite {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .code {
    font-size: 1.6rem;
    font-weight: 800;
    letter-spacing: 0.16em;
  }

  .row {
    display: flex;
    gap: 6px;
  }

  .seats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 10px;
    padding: 14px;
    border-radius: 20px;
  }

  .seat {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 14px 8px;
    border-radius: 14px;
    background: rgb(0 0 0 / 0.22);
    text-align: center;
  }

  .seat.mine {
    outline: 2px solid var(--accent);
  }

  .avatar {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 800;
    font-size: 1.3rem;
  }

  .avatar.offline {
    opacity: 0.45;
  }

  .avatar.empty {
    background: transparent;
    border: 2px dashed rgb(255 255 255 / 0.3);
    color: rgb(255 255 255 / 0.5);
  }

  .name {
    font-weight: 600;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .badges {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 4px;
    min-height: 20px;
  }

  .actions {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
  }

  .big {
    min-height: 54px;
    min-width: 220px;
    font-size: 1.05rem;
  }

  .actions p {
    margin: 0;
    min-height: 1.2em;
  }

  .panel-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
  }

  h2 {
    font-size: 1.05rem;
  }

  .chat {
    display: flex;
    flex-direction: column;
    gap: 8px;
    height: 280px;
  }
</style>
