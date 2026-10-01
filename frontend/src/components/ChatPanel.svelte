<script lang="ts">
  import { tick } from 'svelte'
  import { errorText, t } from '../lib/i18n.svelte'
  import { session } from '../lib/session.svelte'
  import type { TableConnection } from '../lib/table.svelte'
  import { toast } from '../lib/toasts.svelte'

  let { conn }: { conn: TableConnection } = $props()

  let text = $state('')
  let list: HTMLElement | undefined = $state()

  $effect(() => {
    conn.chat.length
    conn.unread = 0
    tick().then(() => list?.scrollTo({ top: list.scrollHeight }))
  })

  async function send(event: SubmitEvent) {
    event.preventDefault()
    const value = text.trim()
    if (!value) return
    text = ''
    try {
      await conn.push('chat', { text: value })
    } catch (reason) {
      toast(errorText(String(reason)), 'error')
    }
  }
</script>

<div class="chat">
  <ul bind:this={list}>
    {#each conn.chat as msg, i (i)}
      <li class:mine={msg.user_id === session.user?.id}>
        <strong>{msg.username}</strong>
        <span>{msg.text}</span>
      </li>
    {/each}
  </ul>
  <form onsubmit={send}>
    <input class="input" bind:value={text} maxlength="300" placeholder={t('table.chat_placeholder')} />
    <button class="btn btn-primary" type="submit" disabled={!text.trim()}>{t('table.send')}</button>
  </form>
</div>

<style>
  .chat {
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-height: 0;
    height: 100%;
  }

  ul {
    flex: 1;
    min-height: 80px;
    overflow-y: auto;
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.92rem;
  }

  strong {
    margin-right: 6px;
    color: var(--muted);
  }

  .mine strong {
    color: var(--accent);
  }

  form {
    display: flex;
    gap: 6px;
  }

  .input {
    min-height: 44px;
  }
</style>
