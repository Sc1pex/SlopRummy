<script lang="ts">
  import { t } from '../lib/i18n.svelte'
  import type { MatchFormat, Rules } from '../lib/types'

  let { rules }: { rules: Rules } = $props()

  function matchLabel(m: MatchFormat) {
    if (m.type === 'single') return t('rules.single')
    return m.type === 'rounds' ? t('rules.rounds', { n: m.n }) : t('rules.points_limit', { n: m.n })
  }
</script>

<dl>
  <dt>{t('rules.match')}</dt>
  <dd>{matchLabel(rules.match)}</dd>
  <dt>{t('rules.opening_min_points')}</dt>
  <dd>{rules.opening_min_points}</dd>
  <dt>{t('rules.max_players')}</dt>
  <dd>{rules.max_players}</dd>
  <dt>{t('rules.turn_timer')}</dt>
  <dd>{rules.turn_timer_ms ? t('rules.seconds', { n: rules.turn_timer_ms / 1000 }) : t('rules.off')}</dd>
  <dt>{t('rules.discard_pickup')}</dt>
  <dd>{rules.discard_pickup === 'must_use' ? t('rules.must_use') : t('rules.free')}</dd>
</dl>

<style>
  dl {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 6px 12px;
    margin: 0;
    font-size: 0.92rem;
  }

  dt {
    color: var(--muted);
  }

  dd {
    margin: 0;
    text-align: right;
    font-weight: 600;
  }
</style>
