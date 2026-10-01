<script lang="ts">
  import { onDestroy } from 'svelte'

  /** `deadline` is a unix timestamp in ms; `total` the full turn length in ms. */
  let { deadline, total, size = 36 }: { deadline: number; total: number; size?: number } = $props()

  let now = $state(Date.now())
  const interval = setInterval(() => (now = Date.now()), 250)
  onDestroy(() => clearInterval(interval))

  const remaining = $derived(Math.max(0, deadline - now))
  const fraction = $derived(Math.min(1, remaining / total))
  const r = $derived(size / 2 - 3)
  const circumference = $derived(2 * Math.PI * r)
  const urgent = $derived(remaining < 10_000)
</script>

<svg width={size} height={size} viewBox="0 0 {size} {size}" class:urgent aria-label="{Math.ceil(remaining / 1000)}s">
  <circle cx={size / 2} cy={size / 2} {r} class="track" />
  <circle
    cx={size / 2}
    cy={size / 2}
    {r}
    class="bar"
    stroke-dasharray={circumference}
    stroke-dashoffset={circumference * (1 - fraction)}
    transform="rotate(-90 {size / 2} {size / 2})"
  />
  <text x="50%" y="50%" dy="0.35em" text-anchor="middle">{Math.ceil(remaining / 1000)}</text>
</svg>

<style>
  circle {
    fill: none;
    stroke-width: 3;
  }

  .track {
    stroke: rgb(255 255 255 / 0.15);
  }

  .bar {
    stroke: var(--accent);
    transition: stroke-dashoffset 0.25s linear;
  }

  .urgent .bar {
    stroke: var(--danger);
  }

  text {
    fill: var(--text);
    font-size: 11px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
</style>
