<script lang="ts">
  import { fly } from 'svelte/transition'
  import { toasts } from '../lib/toasts.svelte'
</script>

<div class="toasts" aria-live="polite">
  {#each toasts as t (t.id)}
    <div class="toast" class:error={t.kind === 'error'} transition:fly={{ y: -16, duration: 180 }}>{t.text}</div>
  {/each}
</div>

<style>
  .toasts {
    position: fixed;
    top: calc(10px + var(--safe-top));
    left: 50%;
    transform: translateX(-50%);
    z-index: 100;
    display: flex;
    flex-direction: column;
    gap: 6px;
    align-items: center;
    pointer-events: none;
    width: max-content;
    max-width: calc(100vw - 32px);
  }

  .toast {
    padding: 8px 14px;
    border-radius: 999px;
    background: var(--surface-2);
    border: 1px solid var(--border);
    box-shadow: 0 6px 20px rgb(0 0 0 / 0.4);
    font-size: 0.9rem;
    font-weight: 600;
  }

  .error {
    border-color: var(--danger);
    color: #ffd7d3;
  }
</style>
