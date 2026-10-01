<script lang="ts">
  import { fade, scale } from 'svelte/transition'
  import { t } from '../../lib/i18n.svelte'
  import type { Player, RoundResult } from '../../lib/types'

  let { result, players, totals }: { result: RoundResult; players: Player[]; totals: Record<string, number> } =
    $props()

  const winner = $derived(result.winner === null ? null : players[result.winner])
  const rows = $derived(
    players
      .map((p) => ({ ...p, round: result.scores[p.seat] ?? 0, total: totals[p.seat] ?? 0 }))
      .sort((a, b) => a.total - b.total),
  )
</script>

<div class="backdrop" transition:fade={{ duration: 150 }}>
  <div class="panel card" transition:scale={{ start: 0.92, duration: 180 }}>
    <h2>{t('game.round_over')}</h2>
    <p class="winner">{winner ? `🎉 ${t('game.winner', { name: winner.username })}` : t('game.no_winner')}</p>
    {#if result.joker_close}<p class="joker">★ {t('game.joker_close')}</p>{/if}
    <table>
      <thead>
        <tr>
          <th></th>
          <th>{t('game.round_points')}</th>
          <th>{t('game.total')}</th>
        </tr>
      </thead>
      <tbody>
        {#each rows as row (row.seat)}
          <tr class:won={row.seat === result.winner}>
            <td class="name">{row.username}</td>
            <td class="tabular">{row.round === 0 ? '0' : `+${row.round}`}</td>
            <td class="tabular total">{row.total}</td>
          </tr>
        {/each}
      </tbody>
    </table>
    <p class="muted next">{t('game.next_round')}</p>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 40;
    display: grid;
    place-items: center;
    background: rgb(0 0 0 / 0.5);
    padding: 16px;
  }

  .card {
    width: min(420px, 100%);
    max-height: 100%;
    overflow: auto;
  }

  h2 {
    font-size: 1.15rem;
  }

  .winner {
    margin: 6px 0;
    font-weight: 700;
    color: var(--accent);
  }

  .joker {
    margin: 0 0 6px;
    color: #c9a0ff;
    font-weight: 600;
    font-size: 0.9rem;
  }

  table {
    width: 100%;
    border-collapse: collapse;
  }

  th {
    text-align: right;
    color: var(--muted);
    font-weight: 600;
    font-size: 0.85rem;
  }

  td {
    text-align: right;
    padding: 5px 0;
    border-top: 1px solid var(--border);
  }

  .name {
    text-align: left;
    font-weight: 600;
  }

  .total {
    font-weight: 800;
  }

  .won td {
    color: var(--accent);
  }

  .next {
    margin: 10px 0 0;
    font-size: 0.85rem;
    text-align: center;
  }
</style>
