<script lang="ts">
  import { fade, scale } from 'svelte/transition'
  import { t } from '../../lib/i18n.svelte'
  import { tileLabel } from '../../lib/tiles'
  import type { Player, RoundResult, Tile } from '../../lib/types'

  interface Props {
    result: RoundResult
    players: Player[]
    totals: Record<string, number>
    atu: Tile | null
  }

  let { result, players, totals, atu }: Props = $props()

  const winner = $derived(result.winner === null ? null : players[result.winner])
  const rows = $derived(
    players
      .map((p) => ({ ...p, b: result.breakdown[p.seat], total: totals[p.seat] ?? 0 }))
      .sort((a, b) => b.total - a.total),
  )
  const signed = (n: number) => (n > 0 ? `+${n}` : String(n))
</script>

<div class="backdrop" transition:fade={{ duration: 150 }}>
  <div class="panel card" transition:scale={{ start: 0.92, duration: 180 }}>
    <h2>{t('game.round_over')}</h2>
    <p class="winner">{winner ? `🎉 ${t('game.winner', { name: winner.username })}` : t('game.no_winner')}</p>
    {#if result.closed_on_board && result.winner !== null}
      <p class="winner">★ {t('game.closed_on_board', { n: result.breakdown[result.winner]?.closing ?? 0 })}</p>
    {/if}
    {#if result.double_close}<p class="note">☺ {t('game.joker_close')}</p>{/if}
    {#if result.atu_multiplier > 1 && atu}<p class="note">{t('game.round_double', { tile: tileLabel(atu) })}</p>{/if}
    <div class="scroll">
      <table>
        <thead>
          <tr>
            <th></th>
            <th>{t('game.laid')}</th>
            <th>{t('game.hand')}</th>
            <th>{t('game.bonus')}</th>
            <th>{t('game.round_points')}</th>
            <th>{t('game.total')}</th>
          </tr>
        </thead>
        <tbody>
          {#each rows as row (row.seat)}
            <tr class:won={row.seat === result.winner}>
              <td class="name">{row.username}</td>
              <td class="tabular">{row.b?.laid ?? 0}</td>
              <td class="tabular">
                {row.b ? -row.b.hand : 0}{#if row.b && !row.b.opened}<span class="tag"> {t('game.not_opened')}</span>{/if}
              </td>
              <td class="tabular">
                {row.b ? signed(row.b.closing + row.b.atu) : 0}{#if row.b && row.b.multiplier > 1}<span class="mult"> ×{row.b.multiplier}</span>{/if}
              </td>
              <td class="tabular strong">{signed(result.scores[row.seat] ?? 0)}</td>
              <td class="tabular strong">{row.total}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
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
    padding: 12px;
  }

  .card {
    width: min(560px, 100%);
    max-height: 100%;
    overflow: auto;
    padding: 12px 14px;
  }

  h2 {
    font-size: 1.1rem;
  }

  .winner {
    margin: 4px 0;
    font-weight: 700;
    color: var(--accent);
  }

  .note {
    margin: 0 0 4px;
    color: #c9a0ff;
    font-weight: 600;
    font-size: 0.85rem;
  }

  .scroll {
    overflow-x: auto;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.88rem;
  }

  th {
    text-align: right;
    color: var(--muted);
    font-weight: 600;
    font-size: 0.78rem;
    padding: 0 0 0 10px;
  }

  td {
    text-align: right;
    padding: 4px 0 4px 10px;
    border-top: 1px solid var(--border);
    white-space: nowrap;
  }

  .name {
    text-align: left;
    font-weight: 600;
    padding-left: 0;
  }

  .strong {
    font-weight: 800;
  }

  .tag {
    color: var(--muted);
    font-size: 0.72rem;
  }

  .mult {
    color: #c9a0ff;
    font-weight: 700;
  }

  .won td {
    color: var(--accent);
  }

  .next {
    margin: 8px 0 0;
    font-size: 0.82rem;
    text-align: center;
  }
</style>
