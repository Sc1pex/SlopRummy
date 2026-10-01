<script lang="ts">
  import { onDestroy } from 'svelte'
  import { api, ApiError } from '../lib/api'
  import { errorText, t } from '../lib/i18n.svelte'
  import { LobbyConnection } from '../lib/lobby.svelte'
  import { navigate } from '../lib/router.svelte'
  import { logout, session } from '../lib/session.svelte'
  import { toast } from '../lib/toasts.svelte'
  import InstallBanner from '../components/InstallBanner.svelte'
  import TopBar from '../components/TopBar.svelte'

  const lobby = new LobbyConnection(session.token!)
  onDestroy(() => lobby.leave())

  let visibility = $state<'public' | 'private'>('public')
  let code = $state('')
  let busy = $state(false)

  async function create() {
    busy = true
    try {
      const { table } = await api.createTable({ preset: 'classic', visibility })
      navigate(`/t/${table.code}`)
    } catch (e) {
      toast(errorText(e instanceof ApiError ? e.reason : 'error'), 'error')
    } finally {
      busy = false
    }
  }

  async function join(event: SubmitEvent) {
    event.preventDefault()
    const value = code.trim().toUpperCase()
    if (!value) return
    try {
      await api.table(value)
      navigate(`/t/${value}`)
    } catch (e) {
      toast(e instanceof ApiError && e.status === 404 ? t('table.not_found') : errorText('error'), 'error')
    }
  }

  async function doLogout() {
    await logout()
    navigate('/', { replace: true })
  }
</script>

<main class="page">
  <TopBar>
    <button class="btn btn-ghost btn-sm" onclick={() => navigate('/history')}>{t('lobby.history')}</button>
  </TopBar>

  <section class="me">
    <div>
      <strong>{session.user?.username}</strong>
      {#if session.user?.guest}<span class="badge">{t('lobby.guest')}</span>{/if}
      <div class="muted small"><span class="dot"></span>{t('lobby.online', { n: lobby.online })}</div>
    </div>
    {#if session.user?.guest}
      <button class="btn btn-sm" onclick={() => navigate('/login')}>{t('lobby.register_cta')}</button>
    {:else}
      <button class="btn btn-ghost btn-sm" onclick={doLogout}>{t('lobby.logout')}</button>
    {/if}
  </section>

  <InstallBanner />

  <section class="grid">
    <div class="panel create">
      <h2>{t('lobby.create')}</h2>
      <div class="segmented" role="radiogroup">
        <button role="radio" aria-checked={visibility === 'public'} class:on={visibility === 'public'} onclick={() => (visibility = 'public')}>
          {t('lobby.public')}
        </button>
        <button role="radio" aria-checked={visibility === 'private'} class:on={visibility === 'private'} onclick={() => (visibility = 'private')}>
          {t('lobby.private')}
        </button>
      </div>
      <button class="btn btn-primary" disabled={busy} onclick={create}>{t('lobby.create')}</button>
    </div>

    <form class="panel join" onsubmit={join}>
      <h2>{t('lobby.join_code')}</h2>
      <input
        class="input code"
        bind:value={code}
        placeholder={t('lobby.code_placeholder')}
        maxlength="8"
        autocapitalize="characters"
        autocomplete="off"
        spellcheck="false"
      />
      <button class="btn" type="submit" disabled={!code.trim()}>{t('lobby.join')}</button>
    </form>
  </section>

  <section>
    <h2 class="section-title">{t('lobby.open_tables')}</h2>
    {#if lobby.tables.length === 0}
      <p class="muted empty">{t('lobby.no_tables')}</p>
    {:else}
      <ul class="tables">
        {#each lobby.tables as table (table.code)}
          <li class="panel table">
            <div class="info">
              <div class="names">
                {table.players.map((p) => p.username).join(', ') || '—'}
              </div>
              <div class="muted small">
                <span class="tabular">{t('lobby.players', { n: table.players.length, max: table.max_players })}</span>
                · <span class="code-label">{table.code}</span>
              </div>
            </div>
            {#if table.status === 'playing'}
              <button class="btn btn-sm" onclick={() => navigate(`/t/${table.code}`)}>{t('lobby.watch')}</button>
            {:else}
              <button
                class="btn btn-primary btn-sm"
                disabled={table.players.length >= table.max_players}
                onclick={() => navigate(`/t/${table.code}`)}>{t('lobby.join')}</button
              >
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </section>
</main>

<style>
  main {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .me {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .small {
    font-size: 0.85rem;
  }

  .dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    margin-right: 6px;
    border-radius: 50%;
    background: var(--ok);
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 12px;
  }

  .create,
  .join {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  h2 {
    font-size: 1.05rem;
  }

  .segmented {
    display: grid;
    grid-template-columns: 1fr 1fr;
    padding: 4px;
    border-radius: 999px;
    background: var(--bg);
    border: 1px solid var(--border);
  }

  .segmented button {
    min-height: 36px;
    border: 0;
    border-radius: 999px;
    background: transparent;
    color: var(--muted);
    font-weight: 600;
  }

  .segmented .on {
    background: var(--surface-2);
    color: var(--text);
  }

  .code {
    text-transform: uppercase;
    letter-spacing: 0.2em;
    text-align: center;
    font-weight: 700;
  }

  .section-title {
    margin-bottom: 8px;
  }

  .empty {
    text-align: center;
    padding: 24px 0;
  }

  .tables {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .table {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
  }

  .info {
    flex: 1;
    min-width: 0;
  }

  .names {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .code-label {
    letter-spacing: 0.08em;
  }
</style>
