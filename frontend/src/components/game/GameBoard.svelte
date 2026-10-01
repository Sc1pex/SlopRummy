<script lang="ts">
  import { untrack } from 'svelte'
  import { meldPoints, sortByRank, sortBySuit } from '../../lib/cards'
  import { device, fullscreenSupported, toggleFullscreen } from '../../lib/device.svelte'
  import { errorText, t } from '../../lib/i18n.svelte'
  import { navigate } from '../../lib/router.svelte'
  import { load, save } from '../../lib/storage'
  import type { TableConnection } from '../../lib/table.svelte'
  import { toast } from '../../lib/toasts.svelte'
  import type { Card, Meld, TableState } from '../../lib/types'
  import { receive, send } from '../../lib/transitions'
  import ChatPanel from '../ChatPanel.svelte'
  import PlayingCard from '../PlayingCard.svelte'
  import Hand from './Hand.svelte'
  import MeldView from './MeldView.svelte'
  import RoundResult from './RoundResult.svelte'
  import TurnTimer from './TurnTimer.svelte'

  let { conn, table }: { conn: TableConnection; table: TableState } = $props()

  // ---- Layout ----
  let innerHeight = $state(window.innerHeight)
  const clamp = (min: number, v: number, max: number) => Math.max(min, Math.min(max, v))
  const handH = $derived(clamp(60, innerHeight * 0.25, 150))
  const meldH = $derived(clamp(38, innerHeight * 0.13, 84))
  const pileH = $derived(clamp(52, innerHeight * 0.19, 116))

  // ---- Game state ----
  const game = $derived(table.game!)
  const round = $derived(game.round)
  const rules = $derived(table.rules)
  const mySeat = $derived(table.my_seat)
  const spectator = $derived(mySeat === null)
  const myTurn = $derived(!!round && round.phase !== 'finished' && round.current === mySeat)
  const drawPhase = $derived(myTurn && round?.phase === 'awaiting_draw')
  const playPhase = $derived(myTurn && round?.phase === 'awaiting_discard')
  const opened = $derived(mySeat !== null && !!round?.opened[mySeat])
  const hand = $derived<Card[]>(round?.hand ?? [])
  const handIds = $derived(new Set(hand.map((c) => c.id)))
  const byId = $derived(new Map(hand.map((c) => [c.id, c])))
  const mustUse = $derived(round?.must_use ?? null)
  const pendingDiscard = $derived(mustUse?.taken_discard != null && handIds.has(mustUse.taken_discard))
  const pendingJoker = $derived(mustUse?.pending_joker != null && handIds.has(mustUse.pending_joker))

  const opponents = $derived.by(() => {
    const n = table.players.length
    if (mySeat === null) return table.players
    return Array.from({ length: n - 1 }, (_, i) => table.players[(mySeat + 1 + i) % n])
  })
  const currentPlayer = $derived(round ? table.players[round.current] : null)
  const timerTotal = $derived(rules.turn_timer_ms ?? 60_000)

  // ---- Local hand state: order, selection, staged melds ----
  const orderKey = `remybun.order.${untrack(() => table.code)}`
  let order = $state<number[]>(load(orderKey, []))
  let selected = $state<number[]>([])
  let staged = $state<number[][]>([])

  // Cards keep the player's arrangement; new cards are appended on the right.
  const orderedHand = $derived.by(() => {
    const known = order.filter((id) => handIds.has(id))
    const fresh = hand.filter((c) => !known.includes(c.id)).map((c) => c.id)
    return [...known, ...fresh].map((id) => byId.get(id)!)
  })
  const stagedIds = $derived(new Set(staged.flat()))
  const visibleHand = $derived(orderedHand.filter((c) => !stagedIds.has(c.id)))

  // Drop selections and staged groups that refer to cards no longer in hand.
  $effect(() => {
    const ids = handIds
    if (selected.some((id) => !ids.has(id))) selected = selected.filter((id) => ids.has(id))
    if (staged.some((g) => g.some((id) => !ids.has(id)))) staged = staged.filter((g) => g.every((id) => ids.has(id)))
  })

  function setOrder(ids: number[]) {
    order = ids
    save(orderKey, ids)
  }

  const cardsOf = (ids: number[]) => ids.map((id) => byId.get(id)!).filter(Boolean)
  const selectedCards = $derived(cardsOf(selected))
  const selectedPoints = $derived(selected.length >= 3 ? meldPoints(selectedCards, rules.max_jokers_per_meld) : null)
  const stagedPoints = $derived(staged.reduce((sum, g) => sum + (meldPoints(cardsOf(g), rules.max_jokers_per_meld) ?? 0), 0))
  const layDownPoints = $derived(stagedPoints + (selectedPoints ?? 0))
  const canLayDown = $derived(playPhase && (staged.length > 0 || selectedPoints !== null))
  const canTargetMelds = $derived(playPhase && selected.length > 0 && (opened || rules.lay_off_before_opening))

  // ---- Actions ----
  async function act(event: string, payload: Record<string, unknown> = {}): Promise<boolean> {
    try {
      await conn.push(event, payload)
      return true
    } catch (reason) {
      toast(errorText(String(reason)), 'error')
      return false
    }
  }

  function toggle(id: number) {
    selected = selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]
  }

  function reorder(id: number, index: number) {
    const ids = orderedHand.map((c) => c.id).filter((x) => x !== id)
    // Index is relative to the visible hand; staged cards keep their place at the end.
    const visible = visibleHand.map((c) => c.id).filter((x) => x !== id)
    const anchor = visible[index]
    const at = anchor === undefined ? ids.length : ids.indexOf(anchor)
    ids.splice(at, 0, id)
    setOrder(ids)
  }

  function group() {
    if (selectedPoints === null) return toast(errorText('invalid_meld'), 'error')
    staged = [...staged, selected]
    selected = []
  }

  function unstage(i: number) {
    staged = staged.filter((_, j) => j !== i)
  }

  async function layDown() {
    const melds = selectedPoints !== null ? [...staged, selected] : staged
    if (await act('lay_down', { melds })) {
      staged = []
      selected = []
    }
  }

  async function discard() {
    const [card] = selected
    if (await act('discard', { card })) selected = []
  }

  function tapMeld(meld: Meld) {
    if (!canTargetMelds) return
    const swap = selected.length === 1 && opened && rules.joker_swap && jokerMatch(meld, byId.get(selected[0])!)
    const request = swap
      ? act('swap_joker', { meld_id: meld.id, card: selected[0] })
      : act('add_to_meld', { meld_id: meld.id, cards: selected })
    request.then((ok) => ok && (selected = []))
  }

  /** Whether `card` is the real card a joker in `meld` stands for. */
  function jokerMatch(meld: Meld, card: Card): boolean {
    if (card.joker) return false
    return meld.cards.some((c) => {
      if (!c.joker || !c.as || c.as.rank !== card.rank) return false
      if (meld.type === 'run') return c.as.suit === card.suit
      return !meld.cards.some((o) => !o.joker && o.suit === card.suit)
    })
  }

  // ---- Melds grouped by owner ----
  const meldGroups = $derived(
    table.players
      .map((p) => ({ player: p, melds: (round?.melds ?? []).filter((m) => m.owner === p.seat) }))
      .filter((g) => g.melds.length > 0),
  )

  const hint = $derived.by(() => {
    if (spectator) return t('game.spectating')
    if (!myTurn) return currentPlayer ? t('game.turn_of', { name: currentPlayer.username }) : ''
    if (pendingJoker) return t('game.must_use_joker')
    if (pendingDiscard) return t('game.must_use_discard')
    if (drawPhase) return t('game.draw_hint')
    if (canTargetMelds) return t('game.select_meld_hint')
    return t('game.discard_hint')
  })

  // ---- Menu / chat ----
  let menuOpen = $state(false)
  let chatOpen = $state(false)

  function leave() {
    if (spectator || confirm(t('game.leave_confirm'))) navigate('/')
  }
</script>

<svelte:window bind:innerHeight />

<div class="board felt" style:--card-h="{meldH}px">
  <!-- Opponents and table info -->
  <header class="top">
    <div class="opponents">
      {#each opponents as p (p.seat)}
        {@const current = round?.current === p.seat && round.phase !== 'finished'}
        <div class="opponent" class:current class:offline={!p.connected}>
          {#if current && table.turn_deadline}
            <TurnTimer deadline={table.turn_deadline} total={timerTotal} size={34} />
          {:else}
            <div class="avatar">{p.username.slice(0, 1).toUpperCase()}</div>
          {/if}
          <div class="who">
            <div class="name">{p.username}</div>
            <div class="meta tabular">
              <span title="cards">🂠 {round?.hand_counts[p.seat] ?? 0}</span>
              <span title="score">Σ {game.totals[p.seat] ?? 0}</span>
              {#if round?.opened[p.seat]}<span class="badge badge-ok">{t('game.opened')}</span>{/if}
              {#if !p.connected}<span class="badge">{t('game.offline')}</span>{/if}
            </div>
          </div>
        </div>
      {/each}
    </div>
    <div class="top-right">
      <span class="badge tabular">{t('game.round', { n: game.rounds_played + (game.phase === 'playing' ? 1 : 0) })}</span>
      <button class="btn btn-ghost btn-sm icon" onclick={() => (chatOpen = true)} aria-label={t('table.chat')}>
        💬{#if conn.unread > 0}<span class="dot"></span>{/if}
      </button>
      <button class="btn btn-ghost btn-sm icon" onclick={() => (menuOpen = !menuOpen)} aria-label="menu">☰</button>
      {#if menuOpen}
        <div class="menu panel">
          {#if fullscreenSupported}
            <button class="btn btn-ghost btn-sm" onclick={() => (toggleFullscreen(), (menuOpen = false))}>
              ⤢ {t('game.fullscreen')}{device.fullscreen ? ' ✓' : ''}
            </button>
          {/if}
          <button class="btn btn-ghost btn-sm btn-danger" onclick={leave}>{t('table.leave')}</button>
        </div>
      {/if}
    </div>
  </header>

  <!-- Stock, discard pile and melds on the table -->
  <section class="middle">
    <div class="piles" style:--card-h="{pileH}px">
      <button class="pile" class:active={drawPhase} disabled={!drawPhase} onclick={() => act('draw_stock')}>
        <PlayingCard faceDown />
        <span class="count tabular">{round?.stock_count ?? 0}</span>
      </button>
      <button
        class="pile"
        class:active={drawPhase && !!round?.discard_top}
        disabled={!drawPhase || !round?.discard_top}
        onclick={() => act('take_discard')}
      >
        {#if round?.discard_top}
          {#key round.discard_top.id}
            <div in:receive={{ key: round.discard_top.id }} out:send={{ key: round.discard_top.id }}>
              <PlayingCard card={round.discard_top} />
            </div>
          {/key}
        {:else}
          <div class="empty-pile"></div>
        {/if}
        <span class="count tabular">{round?.discard_count ?? 0}</span>
      </button>
    </div>

    <div class="melds">
      {#each meldGroups as g (g.player.seat)}
        <div class="meld-group">
          <div class="owner">{g.player.seat === mySeat ? t('game.your_melds') : g.player.username}</div>
          <div class="meld-row">
            {#each g.melds as meld (meld.id)}
              <MeldView {meld} targetable={canTargetMelds} ontap={tapMeld} />
            {/each}
          </div>
        </div>
      {/each}
    </div>
  </section>

  <!-- My controls and hand -->
  {#if !spectator}
    <section class="bottom">
      <div class="controls">
        <div class="me">
          {#if myTurn && table.turn_deadline}
            <TurnTimer deadline={table.turn_deadline} total={timerTotal} size={30} />
          {/if}
          <div class="status">
            <div class="hint" class:my-turn={myTurn}>{hint}</div>
            <div class="meta tabular muted">
              Σ {game.totals[mySeat!] ?? 0}
              {#if opened}
                · <span class="ok">{t('game.opened')}</span>
              {:else if layDownPoints > 0}
                · <span class:ok={layDownPoints >= rules.opening_min_points}>
                  {t('game.points', { n: layDownPoints })} / {t('game.opening_needed', { n: rules.opening_min_points })}
                </span>
              {/if}
            </div>
          </div>
        </div>

        {#if staged.length}
          <div class="staged" style:--card-h="{meldH * 0.8}px">
            {#each staged as g, i (g.join('-'))}
              <button class="staged-group" onclick={() => unstage(i)} aria-label={t('game.clear')}>
                {#each cardsOf(g) as card (card.id)}
                  <div class="slot" in:receive={{ key: card.id }} out:send={{ key: card.id }}>
                    <PlayingCard {card} />
                  </div>
                {/each}
              </button>
            {/each}
          </div>
        {/if}

        <div class="buttons">
          {#if pendingDiscard && playPhase}
            <button class="btn btn-sm" onclick={() => act('return_discard')}>↩ {t('game.return_discard')}</button>
          {/if}
          {#if selected.length >= 3}
            <button class="btn btn-sm" disabled={selectedPoints === null} onclick={group}>
              {t('game.group')}{selectedPoints !== null ? ` · ${selectedPoints}` : ''}
            </button>
          {/if}
          {#if canLayDown}
            <button class="btn btn-primary btn-sm" onclick={layDown}>{t('game.lay_down')}</button>
          {/if}
          {#if playPhase && selected.length === 1}
            <button class="btn btn-primary btn-sm" onclick={discard}>{t('game.discard')}</button>
          {/if}
          {#if selected.length > 0}
            <button class="btn btn-ghost btn-sm" onclick={() => (selected = [])}>✕</button>
          {/if}
          <div class="sort">
            <button class="btn btn-ghost btn-sm" onclick={() => setOrder(sortBySuit(hand).map((c) => c.id))}>♠♥</button>
            <button class="btn btn-ghost btn-sm" onclick={() => setOrder(sortByRank(hand).map((c) => c.id))}>A‑K</button>
          </div>
        </div>
      </div>

      <Hand
        cards={visibleHand}
        {selected}
        highlighted={[pendingDiscard ? mustUse!.taken_discard : null, pendingJoker ? mustUse!.pending_joker : null]}
        cardHeight={handH}
        ontoggle={toggle}
        onreorder={reorder}
      />
    </section>
  {/if}

  {#if game.phase === 'between_rounds' && game.last_result}
    <RoundResult result={game.last_result} players={table.players} totals={game.totals} />
  {/if}

  {#if chatOpen}
    <div class="drawer-backdrop" onclick={() => (chatOpen = false)} role="presentation"></div>
    <aside class="drawer panel">
      <div class="drawer-head">
        <strong>{t('table.chat')}</strong>
        <button class="btn btn-ghost btn-sm" onclick={() => (chatOpen = false)}>✕</button>
      </div>
      <ChatPanel {conn} />
    </aside>
  {/if}
</div>

<style>
  .board {
    position: fixed;
    inset: 0;
    display: grid;
    grid-template-rows: auto 1fr auto;
    gap: 6px;
    padding: calc(6px + var(--safe-top)) calc(8px + var(--safe-right)) calc(4px + var(--safe-bottom))
      calc(8px + var(--safe-left));
    overflow: hidden;
    user-select: none;
    -webkit-user-select: none;
  }

  /* ---- Top ---- */
  .top {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  .opponents {
    flex: 1;
    display: flex;
    gap: 6px;
    min-width: 0;
    overflow-x: auto;
    scrollbar-width: none;
  }

  .opponent {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 3px 10px 3px 4px;
    border-radius: 999px;
    background: rgb(0 0 0 / 0.25);
    border: 2px solid transparent;
    min-width: 0;
  }

  .opponent.current {
    border-color: var(--accent);
  }

  .opponent.offline {
    opacity: 0.55;
  }

  .avatar {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    flex: none;
    border-radius: 50%;
    background: var(--surface-2);
    font-weight: 800;
  }

  .who {
    min-width: 0;
    line-height: 1.15;
  }

  .name {
    font-weight: 700;
    font-size: 0.85rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 14ch;
  }

  .meta {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.75rem;
    white-space: nowrap;
  }

  .top-right {
    position: relative;
    display: flex;
    align-items: center;
    gap: 2px;
  }

  .icon {
    position: relative;
    padding: 0 10px;
  }

  .dot {
    position: absolute;
    top: 6px;
    right: 6px;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--danger);
  }

  .menu {
    position: absolute;
    top: 100%;
    right: 0;
    z-index: 20;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 6px;
    min-width: 180px;
  }

  .menu .btn {
    justify-content: flex-start;
  }

  /* ---- Middle ---- */
  .middle {
    display: flex;
    gap: 10px;
    min-height: 0;
  }

  .piles {
    display: flex;
    gap: 8px;
    align-items: center;
  }

  .pile {
    position: relative;
    padding: 0;
    border: 0;
    background: none;
    border-radius: 10px;
  }

  .pile:disabled {
    cursor: default;
  }

  .pile.active :global(.card) {
    box-shadow:
      0 0 0 3px var(--accent),
      0 4px 12px rgb(0 0 0 / 0.4);
  }

  .count {
    position: absolute;
    bottom: -4px;
    right: -4px;
    min-width: 22px;
    padding: 1px 5px;
    border-radius: 999px;
    background: var(--bg);
    font-size: 0.72rem;
    font-weight: 700;
  }

  .empty-pile {
    width: calc(var(--card-h) * 0.7);
    height: var(--card-h);
    border-radius: 8px;
    border: 2px dashed rgb(255 255 255 / 0.2);
  }

  .melds {
    flex: 1;
    min-width: 0;
    overflow-y: auto;
    display: flex;
    flex-wrap: wrap;
    align-content: flex-start;
    gap: 6px 14px;
  }

  .meld-group {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .owner {
    font-size: 0.72rem;
    font-weight: 700;
    color: rgb(255 255 255 / 0.65);
  }

  .meld-row {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  /* ---- Bottom ---- */
  .bottom {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .controls {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 40px;
  }

  .me {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    flex: 1 1 auto;
  }

  .status {
    min-width: 0;
    line-height: 1.2;
  }

  .hint {
    font-size: 0.85rem;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .hint.my-turn {
    color: var(--accent);
  }

  .status .meta {
    font-size: 0.75rem;
  }

  .ok {
    color: var(--ok);
  }

  .staged {
    display: flex;
    gap: 6px;
  }

  .staged-group {
    display: flex;
    padding: 3px;
    border: 1px dashed var(--accent);
    border-radius: 8px;
    background: rgb(0 0 0 / 0.2);
  }

  .staged-group .slot + .slot {
    margin-left: calc(var(--card-h) * -0.45);
  }

  .buttons {
    display: flex;
    align-items: center;
    gap: 6px;
    flex: none;
  }

  .sort {
    display: flex;
    margin-left: 4px;
    padding-left: 4px;
    border-left: 1px solid rgb(255 255 255 / 0.15);
  }

  /* ---- Chat drawer ---- */
  .drawer-backdrop {
    position: fixed;
    inset: 0;
    z-index: 30;
    background: rgb(0 0 0 / 0.4);
  }

  .drawer {
    position: fixed;
    top: calc(8px + var(--safe-top));
    right: calc(8px + var(--safe-right));
    bottom: calc(8px + var(--safe-bottom));
    z-index: 31;
    width: min(360px, calc(100vw - 16px));
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .drawer-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
</style>
