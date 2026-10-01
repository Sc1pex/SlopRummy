<script lang="ts">
  import type { Snippet } from 'svelte'
  import { navigate } from '../lib/router.svelte'
  import LangToggle from './LangToggle.svelte'

  let { children }: { children?: Snippet } = $props()
</script>

<header>
  <button class="brand" onclick={() => navigate('/')}>
    <img src="/favicon.svg" alt="" width="32" height="32" />
    <span>Remybun</span>
  </button>
  <div class="right">
    {@render children?.()}
    <LangToggle />
  </div>
</header>

<style>
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-bottom: 16px;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0;
    border: 0;
    background: none;
    font-weight: 700;
    font-size: 1.2rem;
  }

  .right {
    display: flex;
    align-items: center;
    gap: 4px;
  }
</style>
