<script lang="ts">
  import type { Card } from '../../lib/types'
  import { receive, send } from '../../lib/transitions'
  import PlayingCard from '../PlayingCard.svelte'

  interface Props {
    cards: Card[]
    selected: number[]
    highlighted: (number | null)[]
    cardHeight: number
    ontoggle: (id: number) => void
    onreorder: (id: number, index: number) => void
  }

  let { cards, selected, highlighted, cardHeight, ontoggle, onreorder }: Props = $props()

  let width = $state(0)
  const cardWidth = $derived(cardHeight * 0.7)
  // Overlap cards so the whole hand always fits on one row.
  const step = $derived(
    cards.length <= 1 ? cardWidth : Math.min(cardWidth * 0.95, (width - cardWidth) / (cards.length - 1)),
  )

  // Center the hand when it doesn't need the full width.
  const offset = $derived(Math.max(0, (width - (cardWidth + step * Math.max(0, cards.length - 1))) / 2))

  // Tap toggles selection; dragging sideways reorders.
  let drag = $state<{ id: number; pointerId: number; startX: number; dx: number; active: boolean } | null>(null)

  function pointerdown(e: PointerEvent, id: number) {
    if (e.button !== 0) return
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    drag = { id, pointerId: e.pointerId, startX: e.clientX, dx: 0, active: false }
  }

  function pointermove(e: PointerEvent) {
    if (!drag || e.pointerId !== drag.pointerId) return
    drag.dx = e.clientX - drag.startX
    if (Math.abs(drag.dx) > 10) drag.active = true
  }

  function pointerup(e: PointerEvent) {
    if (!drag || e.pointerId !== drag.pointerId) return
    const { id, dx, active } = drag
    drag = null

    if (!active) return ontoggle(id)
    const from = cards.findIndex((c) => c.id === id)
    const to = Math.max(0, Math.min(cards.length - 1, from + Math.round(dx / Math.max(step, 1))))
    if (to !== from) onreorder(id, to)
  }

  function keydown(e: KeyboardEvent, id: number) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      ontoggle(id)
    }
  }
</script>

<div class="hand" bind:clientWidth={width} style:--card-h="{cardHeight}px" style:height="{cardHeight * 1.25}px">
  {#each cards as card, i (card.id)}
    {@const dragging = drag?.active && drag.id === card.id}
    <div
      class="slot"
      class:dragging
      role="button"
      tabindex="0"
      aria-pressed={selected.includes(card.id)}
      style:left="{offset + i * step}px"
      style:transform={dragging ? `translateX(${drag!.dx}px)` : undefined}
      style:z-index={dragging ? 100 : i}
      onpointerdown={(e) => pointerdown(e, card.id)}
      onpointermove={pointermove}
      onpointerup={pointerup}
      onpointercancel={() => (drag = null)}
      onkeydown={(e) => keydown(e, card.id)}
      in:receive={{ key: card.id }}
      out:send={{ key: card.id }}
    >
      <PlayingCard {card} selected={selected.includes(card.id)} highlight={highlighted.includes(card.id)} />
    </div>
  {/each}
</div>

<style>
  .hand {
    position: relative;
    width: 100%;
    touch-action: none;
  }

  .slot {
    position: absolute;
    bottom: 0;
    cursor: pointer;
    transition: left 0.2s ease;
    outline: none;
  }

  .slot:focus-visible :global(.card) {
    box-shadow: 0 0 0 3px #7fc4ff;
  }

  .dragging {
    transition: none;
    filter: drop-shadow(0 8px 12px rgb(0 0 0 / 0.5));
  }
</style>
