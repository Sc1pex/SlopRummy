<script lang="ts">
  import { isRed, rankLabel, SUIT_SYMBOL } from '../lib/cards'
  import type { Card } from '../lib/types'

  interface Props {
    card?: Card | null
    faceDown?: boolean
    selected?: boolean
    dimmed?: boolean
    highlight?: boolean
  }

  let { card = null, faceDown = false, selected = false, dimmed = false, highlight = false }: Props = $props()

  const red = $derived(card && !card.joker && isRed(card.suit))
  const jokerAs = $derived(card?.joker && card.as ? rankLabel(card.as.rank) + (card.as.suit ? SUIT_SYMBOL[card.as.suit] : '') : null)
</script>

<!-- Purely visual: containers handle taps and drags. Size comes from --card-h. -->
<div
  class="card"
  class:back={faceDown || !card}
  class:red
  class:joker={card?.joker}
  class:selected
  class:dimmed
  class:highlight
  role="img"
  aria-label={card && !faceDown ? (card.joker ? 'Joker' : `${rankLabel(card.rank)} ${card.suit}`) : 'card'}
>
  {#if card && !faceDown}
    {#if card.joker}
      <span class="corner">★</span>
      <span class="center">★</span>
      {#if jokerAs}<span class="as">{jokerAs}</span>{/if}
    {:else}
      <span class="corner">{rankLabel(card.rank)}<br />{SUIT_SYMBOL[card.suit]}</span>
      <span class="center">{SUIT_SYMBOL[card.suit]}</span>
    {/if}
  {/if}
</div>

<style>
  .card {
    --h: var(--card-h, 96px);
    position: relative;
    flex: none;
    width: calc(var(--h) * 0.7);
    height: var(--h);
    padding: 0;
    border-radius: calc(var(--h) * 0.08);
    border: 1px solid var(--card-edge);
    background: var(--card-face);
    color: var(--card-black);
    box-shadow: 0 1px 3px rgb(0 0 0 / 0.35);
    font-family: Georgia, 'Times New Roman', serif;
    transition:
      transform 0.15s ease,
      box-shadow 0.15s ease,
      opacity 0.15s;
    user-select: none;
    -webkit-user-select: none;
  }

  .red {
    color: var(--card-red);
  }

  .joker {
    color: #6b3fa0;
  }

  .corner {
    position: absolute;
    top: calc(var(--h) * 0.05);
    left: calc(var(--h) * 0.06);
    font-size: calc(var(--h) * 0.2);
    font-weight: 700;
    line-height: 0.95;
    text-align: center;
  }

  .center {
    position: absolute;
    right: calc(var(--h) * 0.08);
    bottom: calc(var(--h) * 0.05);
    font-size: calc(var(--h) * 0.34);
    line-height: 1;
  }

  .as {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 2px;
    font-size: calc(var(--h) * 0.14);
    font-family: system-ui, sans-serif;
    font-weight: 700;
    color: #6b3fa0;
    text-align: center;
  }

  .back {
    border-color: #0a2a1f;
    background:
      repeating-linear-gradient(45deg, rgb(255 255 255 / 0.08) 0 4px, transparent 4px 8px),
      linear-gradient(135deg, #a3302c, #6e1d1b);
    box-shadow:
      inset 0 0 0 3px var(--card-face),
      0 1px 3px rgb(0 0 0 / 0.35);
  }

  .selected {
    transform: translateY(-22%);
    box-shadow:
      0 0 0 3px var(--accent),
      0 6px 14px rgb(0 0 0 / 0.4);
  }

  .highlight {
    box-shadow:
      0 0 0 3px var(--accent),
      0 1px 3px rgb(0 0 0 / 0.35);
  }

  .dimmed {
    opacity: 0.5;
  }
</style>
