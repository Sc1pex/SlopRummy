<script lang="ts">
  import { COLOR_HEX } from '../lib/tiles'
  import type { Tile } from '../lib/types'

  interface Props {
    tile?: Tile | null
    faceDown?: boolean
    selected?: boolean
    highlight?: boolean
  }

  let { tile = null, faceDown = false, selected = false, highlight = false }: Props = $props()

  const color = $derived(tile && !tile.joker ? COLOR_HEX[tile.color] : COLOR_HEX.red)
  const jokerAs = $derived(tile?.joker && tile.as ? String(tile.as.rank) : null)
</script>

<!-- Purely visual: containers handle taps and drags. Size comes from --tile-h. -->
<div
  class="tile"
  class:back={faceDown || !tile}
  class:selected
  class:highlight
  style:--ink={color}
  role="img"
  aria-label={tile && !faceDown ? (tile.joker ? 'Joker' : `${tile.rank} ${tile.color}`) : 'tile'}
>
  {#if tile && !faceDown}
    {#if tile.joker}
      <span class="joker">☺</span>
      {#if jokerAs}<span class="as">{jokerAs}</span>{/if}
    {:else}
      <span class="num">{tile.rank}</span>
      <span class="dot"></span>
    {/if}
  {/if}
</div>

<style>
  .tile {
    --h: var(--tile-h, 64px);
    position: relative;
    flex: none;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    width: calc(var(--h) * 0.72);
    height: var(--h);
    border-radius: calc(var(--h) * 0.1);
    background: linear-gradient(180deg, #fffdf6 0%, #f3ecdc 100%);
    box-shadow:
      inset 0 -3px 0 #d8ccb2,
      0 1px 2px rgb(0 0 0 / 0.35);
    color: var(--ink);
    user-select: none;
    -webkit-user-select: none;
    transition:
      transform 0.15s ease,
      box-shadow 0.15s ease;
  }

  .num {
    font-family: 'Arial Rounded MT Bold', 'Trebuchet MS', system-ui, sans-serif;
    font-weight: 800;
    font-size: calc(var(--h) * 0.46);
    line-height: 1;
    letter-spacing: -0.04em;
    margin-top: calc(var(--h) * -0.08);
  }

  .dot {
    width: calc(var(--h) * 0.13);
    height: calc(var(--h) * 0.13);
    margin-top: calc(var(--h) * 0.06);
    border-radius: 50%;
    border: max(1.5px, calc(var(--h) * 0.025)) solid var(--ink);
    opacity: 0.7;
  }

  .joker {
    font-size: calc(var(--h) * 0.56);
    line-height: 1;
    color: #c8322f;
  }

  .as {
    position: absolute;
    right: calc(var(--h) * 0.06);
    bottom: calc(var(--h) * 0.06);
    font: 700 calc(var(--h) * 0.17) / 1 system-ui, sans-serif;
    color: #6b6152;
  }

  .back {
    background:
      radial-gradient(circle at 50% 50%, #e9dfc8 0 22%, transparent 23%),
      linear-gradient(180deg, #f6efdf 0%, #e7dcc4 100%);
  }

  .selected {
    transform: translateY(-14%);
    box-shadow:
      inset 0 -3px 0 #d8ccb2,
      0 0 0 3px var(--accent),
      0 6px 12px rgb(0 0 0 / 0.4);
  }

  .highlight {
    box-shadow:
      inset 0 -3px 0 #d8ccb2,
      0 0 0 3px var(--accent),
      0 1px 2px rgb(0 0 0 / 0.35);
  }
</style>
