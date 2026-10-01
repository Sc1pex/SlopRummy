<script lang="ts">
  import type { Meld } from '../../lib/types'
  import { receive, send } from '../../lib/transitions'
  import Tile from '../Tile.svelte'

  interface Props {
    meld: Meld
    targetable: boolean
    ontap: (meld: Meld) => void
  }

  let { meld, targetable, ontap }: Props = $props()
</script>

<button class="meld" class:targetable disabled={!targetable} onclick={() => ontap(meld)} aria-label="meld {meld.id}">
  {#each meld.cards as card (card.id)}
    <div class="slot" in:receive={{ key: card.id }} out:send={{ key: card.id }}>
      <Tile tile={card} />
    </div>
  {/each}
</button>

<style>
  .meld {
    display: flex;
    gap: 1px;
    padding: 3px;
    border: 2px solid transparent;
    border-radius: 10px;
    background: rgb(0 0 0 / 0.14);
  }

  .meld:disabled {
    cursor: default;
  }

  .targetable {
    border-color: color-mix(in srgb, var(--accent) 70%, transparent);
    background: color-mix(in srgb, var(--accent) 12%, transparent);
    animation: pulse 1.6s ease-in-out infinite;
  }

  @keyframes pulse {
    50% {
      border-color: color-mix(in srgb, var(--accent) 25%, transparent);
    }
  }
</style>
