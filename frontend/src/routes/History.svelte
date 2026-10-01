<script lang="ts">
  import { api } from '../lib/api'
  import { i18n, t } from '../lib/i18n.svelte'
  import { session } from '../lib/session.svelte'
  import type { HistoryGame } from '../lib/types'
  import TopBar from '../components/TopBar.svelte'

  let games = $state<HistoryGame[] | null>(null)
  let failed = $state(false)

  api
    .history()
    .then((r) => (games = r.games))
    .catch(() => (failed = true))

  const formatDate = (iso: string) =>
    new Date(iso).toLocaleString(i18n.lang === 'ro' ? 'ro-RO' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' })
</script>

<main class="page">
  <TopBar />
  <h1>{t('history.title')}</h1>

  {#if failed}
    <p class="muted">{t('errors.network_error')}</p>
  {:else if games === null}
    <p class="muted">…</p>
  {:else if games.length === 0}
    <p class="muted">{t('history.empty')}</p>
  {:else}
    <ul>
      {#each games as game (game.id)}
        {@const won = game.winner_id === session.user?.id}
        <li class="panel">
          <div class="head">
            <span class="muted">{formatDate(game.started_at)}</span>
            {#if game.status === 'abandoned'}
              <span class="badge">{t('history.abandoned')}</span>
            {:else if won}
              <span class="badge badge-ok">{t('history.won')}</span>
            {:else}
              <span class="badge">{t('history.lost')}</span>
            {/if}
          </div>
          <table>
            <tbody>
              {#each [...game.players].sort((a, b) => (a.final_score ?? 0) - (b.final_score ?? 0)) as p (p.seat)}
                <tr class:me={p.user_id === session.user?.id}>
                  <td>{p.username ?? '—'}</td>
                  <td class="tabular score">{p.final_score ?? '—'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </li>
      {/each}
    </ul>
  {/if}
</main>

<style>
  h1 {
    font-size: 1.4rem;
    margin-bottom: 16px;
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
    font-size: 0.9rem;
  }

  table {
    width: 100%;
    border-collapse: collapse;
  }

  td {
    padding: 4px 0;
  }

  .score {
    text-align: right;
  }

  .me td {
    color: var(--accent);
    font-weight: 600;
  }
</style>
