<script lang="ts">
  import { onMount } from 'svelte'
  import { i18n } from './lib/i18n.svelte'
  import { router } from './lib/router.svelte'
  import { initSession, session } from './lib/session.svelte'
  import Toasts from './components/Toasts.svelte'
  import Lobby from './routes/Lobby.svelte'
  import Login from './routes/Login.svelte'
  import History from './routes/History.svelte'
  import Table from './routes/Table.svelte'

  onMount(() => {
    document.documentElement.lang = i18n.lang
    initSession()
  })

  // Where to go after logging in when the current page needs a session.
  const next = $derived(location.pathname + location.search)
</script>

{#if !session.ready}
  <div class="splash" aria-busy="true"><img src="/favicon.svg" alt="" width="72" height="72" /></div>
{:else if router.route.name === 'login'}
  <Login next={router.route.next} />
{:else if !session.user}
  <Login next={next === '/' ? undefined : next} />
{:else if router.route.name === 'table'}
  {#key router.route.code}
    <Table code={router.route.code} />
  {/key}
{:else if router.route.name === 'history'}
  <History />
{:else}
  <Lobby />
{/if}

<Toasts />

<style>
  .splash {
    display: grid;
    place-items: center;
    min-height: 100dvh;
  }
</style>
