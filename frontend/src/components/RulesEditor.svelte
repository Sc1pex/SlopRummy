<script lang="ts">
  import { untrack } from 'svelte'
  import { t } from '../lib/i18n.svelte'
  import type { Rules } from '../lib/types'

  interface Props {
    rules: Rules
    preset: string
    onsave: (preset: string, overrides: Record<string, unknown>) => void
    oncancel: () => void
  }

  let { rules, preset, onsave, oncancel }: Props = $props()

  // Local editable copies of the fields players commonly change, taken once on open.
  const initial = untrack(() => rules)
  let opening = $state(initial.opening_min_points)
  let maxPlayers = $state(initial.max_players)
  let notOpened = $state(initial.not_opened_penalty)
  let timer = $state(initial.turn_timer_ms === null ? 0 : initial.turn_timer_ms / 1000)
  let matchType = $state(initial.match.type)
  let matchN = $state('n' in initial.match ? initial.match.n : 4)

  function save(event: SubmitEvent) {
    event.preventDefault()
    onsave(preset, {
      opening_min_points: Number(opening),
      max_players: Number(maxPlayers),
      not_opened_penalty: Number(notOpened),
      turn_timer_ms: Number(timer) === 0 ? null : Number(timer) * 1000,
      match: matchType === 'single' ? { type: 'single' } : { type: matchType, n: Number(matchN) },
    })
  }
</script>

<form onsubmit={save}>
  <label>
    <span>{t('rules.match')}</span>
    <div class="pair">
      <select class="input" bind:value={matchType}>
        <option value="rounds">{t('rules.rounds', { n: '#' })}</option>
        <option value="points_limit">{t('rules.points_limit', { n: '#' })}</option>
        <option value="single">{t('rules.single')}</option>
      </select>
      {#if matchType !== 'single'}
        <input class="input num" type="number" min="1" max={matchType === 'rounds' ? 20 : 5000} bind:value={matchN} />
      {/if}
    </div>
  </label>
  <label>
    <span>{t('rules.opening_min_points')}</span>
    <input class="input" type="number" min="0" max="200" bind:value={opening} />
  </label>
  <label>
    <span>{t('rules.not_opened_penalty')}</span>
    <input class="input" type="number" min="0" max="1000" step="10" bind:value={notOpened} />
  </label>
  <label>
    <span>{t('rules.max_players')}</span>
    <select class="input" bind:value={maxPlayers}>
      {#each [2, 3, 4] as n (n)}<option value={n}>{n}</option>{/each}
    </select>
  </label>
  <label>
    <span>{t('rules.turn_timer')}</span>
    <select class="input" bind:value={timer}>
      <option value={0}>{t('rules.off')}</option>
      {#each [30, 60, 90, 120] as s (s)}<option value={s}>{t('rules.seconds', { n: s })}</option>{/each}
    </select>
  </label>
  <div class="buttons">
    <button type="button" class="btn btn-ghost" onclick={oncancel}>{t('table.cancel')}</button>
    <button type="submit" class="btn btn-primary">{t('table.save')}</button>
  </div>
</form>

<style>
  form {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.9rem;
  }

  .pair {
    display: flex;
    gap: 6px;
  }

  .num {
    width: 100px;
    flex: none;
  }

  .buttons {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
</style>
