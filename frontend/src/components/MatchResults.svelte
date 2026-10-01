<script lang="ts">
  import { t } from '../lib/i18n.svelte'
  import type { MatchResult } from '../lib/types'

  let { result }: { result: MatchResult } = $props()

  const rows = $derived(
    result.players
      .map((p, seat) => ({
        ...p,
        seat,
        rounds: result.rounds.map((r) => r.scores[seat] ?? 0),
        total: result.totals[seat] ?? 0,
      }))
      .sort((a, b) => a.total - b.total),
  )
  const winnerNames = $derived(result.winners.map((s) => result.players[s]?.username).join(', '))
</script>

<section class="panel results">
  <h2>{t('game.match_over')}</h2>
  <p class="winner">🏆 {t('game.match_winner', { name: winnerNames })}</p>
  <div class="scroll">
    <table>
      <thead>
        <tr>
          <th></th>
          {#each result.rounds as _, i (i)}<th class="tabular">{i + 1}</th>{/each}
          <th>{t('game.total')}</th>
        </tr>
      </thead>
      <tbody>
        {#each rows as row (row.seat)}
          <tr class:win={result.winners.includes(row.seat)}>
            <td class="name">{row.username}</td>
            {#each row.rounds as score, i (i)}<td class="tabular">{score}</td>{/each}
            <td class="tabular total">{row.total}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</section>

<style>
  .results {
    border-color: var(--accent);
  }

  h2 {
    font-size: 1.1rem;
  }

  .winner {
    margin: 4px 0 10px;
    font-weight: 700;
    color: var(--accent);
  }

  .scroll {
    overflow-x: auto;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.92rem;
  }

  th {
    color: var(--muted);
    font-weight: 600;
    text-align: right;
    padding: 4px 6px;
  }

  td {
    text-align: right;
    padding: 4px 6px;
    border-top: 1px solid var(--border);
  }

  .name {
    text-align: left;
    font-weight: 600;
  }

  .total {
    font-weight: 800;
  }

  .win td {
    color: var(--accent);
  }
</style>
