<script lang="ts">
  import { device, isIOS, isStandalone, promptInstall } from '../lib/device.svelte'
  import { t } from '../lib/i18n.svelte'
  import { load, save } from '../lib/storage'

  let dismissed = $state(load('remybun.install_dismissed', false))
  const show = $derived(!isStandalone && !dismissed && (isIOS || device.canInstall))

  function dismiss() {
    dismissed = true
    save('remybun.install_dismissed', true)
  }
</script>

{#if show}
  <div class="banner panel">
    <img src="/apple-touch-icon.png" alt="" width="40" height="40" />
    <p>{isIOS ? t('install.ios') : t('install.android')}</p>
    <div class="actions">
      {#if !isIOS}
        <button class="btn btn-primary btn-sm" onclick={promptInstall}>{t('install.button')}</button>
      {/if}
      <button class="btn btn-ghost btn-sm" onclick={dismiss}>{t('install.dismiss')}</button>
    </div>
  </div>
{/if}

<style>
  .banner {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 12px;
    padding: 12px;
  }

  img {
    border-radius: 10px;
  }

  p {
    flex: 1 1 200px;
    margin: 0;
    font-size: 0.9rem;
  }

  .actions {
    display: flex;
    gap: 6px;
    margin-left: auto;
  }
</style>
