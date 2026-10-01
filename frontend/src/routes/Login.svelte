<script lang="ts">
  import { ApiError } from '../lib/api'
  import { errorText, t } from '../lib/i18n.svelte'
  import { navigate } from '../lib/router.svelte'
  import { login, playAsGuest, register, session } from '../lib/session.svelte'
  import LangToggle from '../components/LangToggle.svelte'

  let { next }: { next?: string } = $props()

  // A guest landing here is upgrading their account.
  const upgrading = $derived(!!session.user?.guest)
  let mode = $state<'welcome' | 'login' | 'register'>(session.user?.guest ? 'register' : 'welcome')

  let username = $state('')
  let email = $state('')
  let password = $state('')
  let busy = $state(false)
  let error = $state<string | null>(null)
  let fieldErrors = $state<Record<string, string[]>>({})

  async function run(action: () => Promise<void>) {
    busy = true
    error = null
    fieldErrors = {}
    try {
      await action()
      navigate(next && next.startsWith('/') ? next : '/', { replace: true })
    } catch (e) {
      if (e instanceof ApiError) {
        error = errorText(e.reason)
        fieldErrors = e.fields
      } else {
        error = errorText('error')
      }
    } finally {
      busy = false
    }
  }

  function submit(event: SubmitEvent) {
    event.preventDefault()
    if (mode === 'login') run(() => login(email, password))
    else run(() => register({ username, email, password }))
  }
</script>

<main class="page wrap">
  <header>
    {#if upgrading}
      <button class="btn btn-ghost btn-sm" onclick={() => navigate('/')}>← {t('auth.back')}</button>
    {:else}
      <span></span>
    {/if}
    <LangToggle />
  </header>

  <div class="brand">
    <img src="/favicon.svg" alt="" width="88" height="88" />
    <h1>Remybun</h1>
    <p class="muted">{t('welcome.tagline')}</p>
  </div>

  {#if mode === 'welcome'}
    <div class="stack">
      <button class="btn btn-primary big" disabled={busy} onclick={() => run(playAsGuest)}>{t('welcome.guest')}</button>
      <button class="btn big" onclick={() => (mode = 'login')}>{t('welcome.login')}</button>
      {#if error}<p class="error">{error}</p>{/if}
    </div>
  {:else}
    <form class="panel stack" onsubmit={submit}>
      <h2>{upgrading ? t('auth.upgrade_title') : mode === 'login' ? t('auth.login_title') : t('auth.register_title')}</h2>
      {#if upgrading}<p class="muted hint">{t('auth.upgrade_hint')}</p>{/if}

      {#if mode === 'register'}
        <label>
          <span>{t('auth.username')}</span>
          <input class="input" bind:value={username} autocomplete="username" required minlength="3" maxlength="20" />
          {#if fieldErrors.username}<small class="error">{fieldErrors.username[0]}</small>{/if}
        </label>
      {/if}
      <label>
        <span>{t('auth.email')}</span>
        <input class="input" type="email" bind:value={email} autocomplete="email" required />
        {#if fieldErrors.email}<small class="error">{fieldErrors.email[0]}</small>{/if}
      </label>
      <label>
        <span>{t('auth.password')}</span>
        <input
          class="input"
          type="password"
          bind:value={password}
          autocomplete={mode === 'login' ? 'current-password' : 'new-password'}
          required
          minlength={mode === 'register' ? 8 : undefined}
        />
        {#if fieldErrors.password}<small class="error">{fieldErrors.password[0]}</small>{/if}
      </label>

      {#if error}<p class="error">{error}</p>{/if}

      <button class="btn btn-primary" type="submit" disabled={busy}>
        {mode === 'login' ? t('auth.login_submit') : t('auth.register_submit')}
      </button>

      {#if !upgrading}
        <button type="button" class="btn btn-ghost btn-sm" onclick={() => (mode = mode === 'login' ? 'register' : 'login')}>
          {mode === 'login' ? t('auth.no_account') : t('auth.have_account')}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={() => (mode = 'welcome')}>← {t('auth.back')}</button>
      {/if}
    </form>
  {/if}
</main>

<style>
  .wrap {
    max-width: 420px;
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    gap: 24px;
  }

  header {
    display: flex;
    justify-content: space-between;
  }

  .brand {
    text-align: center;
    margin-top: 4vh;
  }

  .brand h1 {
    font-size: 2.2rem;
    margin-top: 8px;
    letter-spacing: 0.02em;
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .big {
    min-height: 54px;
    font-size: 1.05rem;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.9rem;
  }

  .hint {
    margin: 0;
    font-size: 0.9rem;
  }

  .error {
    color: var(--danger);
    margin: 0;
  }
</style>
