<script lang="ts">
  import { untrack } from 'svelte'
  import { device, fullscreenSupported, toggleFullscreen } from '../../lib/device.svelte'
  import { errorText, t } from '../../lib/i18n.svelte'
  import { arrangeByColor, arrangeByNumber, groupsFromSelection, moveTile, placeTiles, RACK_ROWS, type Layout } from '../../lib/rack'
  import { navigate } from '../../lib/router.svelte'
  import { load, save } from '../../lib/storage'
  import type { TableConnection } from '../../lib/table.svelte'
  import { meldPoints } from '../../lib/tiles'
  import { toast } from '../../lib/toasts.svelte'
  import type { Meld, TableState, Tile as TileT } from '../../lib/types'
  import { receive, send } from '../../lib/transitions'
  import ChatPanel from '../ChatPanel.svelte'
  import Tile from '../Tile.svelte'
  import Exchange from './Exchange.svelte'
  import MeldView from './MeldView.svelte'
  import Rack from './Rack.svelte'
  import RoundResult from './RoundResult.svelte'
  import TurnTimer from './TurnTimer.svelte'

  let { conn, table }: { conn: TableConnection; table: TableState } = $props()

  const COLS = 16
  const SLOTS = COLS * RACK_ROWS

  // ---- Layout ----
  // Sizes come from the board's measured box, which CSS keeps within the visible area
  // (100dvh). window.innerHeight can be larger than what is on screen, e.g. on Firefox for
  // Android while its toolbars are showing, which would push the rack off the bottom.
  let boardW = $state(window.innerWidth)
  let boardH = $state(window.innerHeight)
  // The rack takes the full width and at most ~40% of the height.
  const tileH = $derived(
    Math.max(
      24,
      Math.floor(
        Math.min((boardW - 32 - 12 - (COLS - 1) * 3) / COLS / 0.72, (boardH * 0.4 - 24) / (RACK_ROWS * 1.16), 92),
      ),
    ),
  )
  const meldTileH = $derived(Math.max(28, Math.min(64, Math.floor(boardH * 0.11))))
  const pileTileH = $derived(Math.max(40, Math.min(96, Math.floor(boardH * 0.17))))

  // ---- Game state ----
  const game = $derived(table.game!)
  const round = $derived(game.round)
  const rules = $derived(table.rules)
  const mySeat = $derived(table.my_seat)
  const spectator = $derived(mySeat === null)
  const exchanging = $derived(round?.phase === 'exchange')
  const playing = $derived(round?.phase === 'awaiting_draw' || round?.phase === 'awaiting_discard')
  const myTurn = $derived(!!round && playing && round.current === mySeat)
  const drawPhase = $derived(myTurn && round?.phase === 'awaiting_draw')
  const playPhase = $derived(myTurn && round?.phase === 'awaiting_discard')
  const opened = $derived(mySeat !== null && !!round?.opened[mySeat])
  const firstTurn = $derived(mySeat !== null && !!round?.first_turn[mySeat])
  const openedNow = $derived(!!round?.turn?.opened_now)
  const hand = $derived<TileT[]>(round?.hand ?? [])
  const discard = $derived<TileT[]>(round?.discard ?? [])

  const opponents = $derived.by(() => {
    const n = table.players.length
    if (mySeat === null) return table.players
    return Array.from({ length: n - 1 }, (_, i) => table.players[(mySeat + 1 + i) % n])
  })
  const currentPlayer = $derived(round ? table.players[round.current] : null)
  const timerTotal = $derived(rules.turn_timer_ms ?? 60_000)

  // ---- Taking from the discard pile ----
  // Tapping a takeable tile puts it (and, for opened players, every tile after it) on the
  // rack provisionally. The take is only sent together with the melds that use the tile.
  let taking = $state<{ tile: number; ids: number[] } | null>(null)

  function takeable(index: number): boolean {
    if (!drawPhase || firstTurn || !round) return false
    if (discard[index].id === round.blocked_discard) return false
    return opened || index === discard.length - 1
  }

  function startTake(index: number) {
    if (!takeable(index)) return
    const ids = discard.slice(index).map((t) => t.id)
    taking = { tile: ids[0], ids }
    selected = [ids[0]]
  }

  function cancelTake() {
    taking = null
    selected = []
  }

  $effect(() => {
    if (!drawPhase && taking) taking = null
  })

  const takenTiles = $derived(taking ? discard.filter((t) => taking!.ids.includes(t.id)) : [])
  const rackTiles = $derived([...hand, ...takenTiles])
  const rackIds = $derived(rackTiles.map((t) => t.id))
  const byId = $derived(new Map(rackTiles.map((t) => [t.id, t])))
  const pendingJoker = $derived(round?.turn?.pending_joker != null && hand.some((t) => t.id === round!.turn!.pending_joker))

  // ---- Rack layout (saved on this device per table) ----
  const rackKey = `remybun.rack.${untrack(() => table.code)}`
  let saved = $state<Layout>(load<Layout>(rackKey, {}))

  // A saved layout that knows less than half the current tiles belongs to an earlier deal.
  const layout = $derived.by(() => {
    const known = rackIds.filter((id) => saved[id] !== undefined).length
    return placeTiles(rackIds, known * 2 >= rackIds.length ? saved : {}, SLOTS)
  })

  // Keep the saved layout in step with tiles placed automatically (deal, draws, takes).
  $effect(() => {
    save(rackKey, layout)
    if (rackIds.some((id) => untrack(() => saved[id]) === undefined)) saved = layout
  })

  function moveOnRack(id: number, slot: number) {
    saved = moveTile(layout, id, slot)
  }

  // ---- Selection ----
  let selected = $state<number[]>([])

  $effect(() => {
    const ids = new Set(rackIds)
    if (selected.some((id) => !ids.has(id))) selected = selected.filter((id) => ids.has(id))
  })

  function toggle(id: number) {
    selected = selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]
  }

  // Selected tiles that touch on the rack form one meld each.
  const groups = $derived(groupsFromSelection(layout, selected, COLS))
  const groupPoints = $derived(
    groups.map((g) => meldPoints(g.map((id) => byId.get(id)!).filter(Boolean), rules.max_jokers_per_meld)),
  )
  const groupsValid = $derived(groups.length > 0 && groups.every((g, i) => g.length >= 3 && groupPoints[i] !== null))
  const layDownPoints = $derived(groupPoints.reduce<number>((sum, p) => sum + (p ?? 0), 0))
  const canMeld = $derived(!firstTurn && (playPhase || !!taking))
  const canLayDown = $derived(canMeld && groupsValid && (!taking || selected.includes(taking.tile)))
  const canTargetMelds = $derived(canMeld && selected.length > 0 && opened && !openedNow)

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

  async function layDown() {
    if (!groupsValid) return toast(errorText('invalid_meld'), 'error')
    const ok = taking
      ? await act('take_discard', { card: taking.tile, melds: groups })
      : await act('lay_down', { melds: groups })
    if (ok) {
      taking = null
      selected = []
    }
  }

  async function discardTile() {
    const [card] = selected
    if (await act('discard', { card })) selected = []
  }

  async function tapMeld(meld: Meld) {
    if (!canTargetMelds) return
    let ok: boolean
    if (taking) {
      ok = await act('take_discard', { card: taking.tile, additions: [{ meld_id: meld.id, cards: selected }] })
    } else if (selected.length === 1 && rules.joker_swap && jokerMatch(meld, byId.get(selected[0])!)) {
      ok = await act('swap_joker', { meld_id: meld.id, card: selected[0] })
    } else {
      ok = await act('add_to_meld', { meld_id: meld.id, cards: selected })
    }
    if (ok) {
      taking = null
      selected = []
    }
  }

  /** Whether `tile` is the real tile a joker in `meld` stands for. */
  function jokerMatch(meld: Meld, tile: TileT): boolean {
    if (tile.joker) return false
    return meld.cards.some((c) => {
      if (!c.joker || !c.as || c.as.rank !== tile.rank) return false
      if (meld.type === 'run') return c.as.color === tile.color
      return !meld.cards.some((o) => !o.joker && o.color === tile.color)
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
    if (exchanging) return t('exchange.title')
    if (!myTurn) return currentPlayer ? t('game.turn_of', { name: currentPlayer.username }) : ''
    if (firstTurn) return t('game.first_turn')
    if (pendingJoker) return t('game.must_use_joker')
    if (taking) return t('game.take_hint')
    if (drawPhase) return t('game.draw_hint')
    if (openedNow) return t('game.opening_turn')
    if (!opened) return t('game.opening_rule', { n: rules.opening_min_points })
    if (canTargetMelds) return t('game.select_meld_hint')
    return t('game.discard_hint')
  })

  // The round result is shown after the round is gone; remember its atu.
  let lastAtu = $state<TileT | null>(null)
  $effect(() => {
    if (round?.atu) lastAtu = round.atu
  })

  // ---- Menu / chat ----
  let menuOpen = $state(false)
  let chatOpen = $state(false)

  function leave() {
    if (spectator || confirm(t('game.leave_confirm'))) navigate('/')
  }
</script>

<div class="board felt" style:--tile-h="{meldTileH}px" bind:clientWidth={boardW} bind:clientHeight={boardH}>
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
              <span class="count-tiles"><i></i>{round?.hand_counts[p.seat] ?? 0}</span>
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

  <!-- Stock and atu, the discard row, and melds on the table (or the duplicate exchange) -->
  <section class="middle">
    <div class="piles" style:--tile-h="{pileTileH}px">
      <button class="pile" class:active={drawPhase && !taking} disabled={!drawPhase || !!taking} onclick={() => act('draw_stock')}>
        <div class="stack"><Tile faceDown /></div>
        <span class="count tabular">{round?.stock_count ?? 0}</span>
      </button>
      {#if round?.atu}
        <div class="atu" style:--tile-h="{Math.round(pileTileH * 0.7)}px" title={t('game.atu')}>
          <Tile tile={round.atu} />
          <span class="atu-label">{t('game.atu')}{round.atu_multiplier > 1 ? ' ×2' : ''}</span>
        </div>
      {/if}
    </div>

    <div class="table-area">
      {#if discard.length > 0}
        <div class="discards" aria-label={t('game.discards')}>
          {#each discard as tile, i (tile.id)}
            {@const blocked = tile.id === round?.blocked_discard}
            {@const inTake = taking?.ids.includes(tile.id)}
            <button
              class="discard"
              class:blocked
              class:takeable={!taking && takeable(i)}
              class:in-take={inTake}
              disabled={!!taking || !takeable(i)}
              onclick={() => startTake(i)}
            >
              <div in:receive={{ key: tile.id }} out:send={{ key: tile.id }}><Tile {tile} /></div>
              {#if blocked}<span class="lock">🔒</span>{/if}
            </button>
          {/each}
        </div>
      {/if}

      {#if exchanging && round}
        <Exchange {round} players={table.players} {mySeat} {act} />
      {:else}
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
      {/if}
    </div>
  </section>

  <!-- My controls and rack -->
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
                · <span class:ok={groupsValid && layDownPoints >= rules.opening_min_points}>
                  {t('game.points', { n: layDownPoints })} / {t('game.opening_needed', { n: rules.opening_min_points })}
                </span>
              {/if}
            </div>
          </div>
        </div>

        <div class="buttons">
          {#if taking}
            <button class="btn btn-ghost btn-sm" onclick={cancelTake}>{t('game.cancel_take')}</button>
          {/if}
          {#if canMeld && selected.length >= 3}
            <button class="btn btn-primary btn-sm" disabled={!canLayDown} onclick={layDown}>
              {taking ? t('game.take_lay_down') : t('game.lay_down')}{groupsValid ? ` · ${layDownPoints}` : ''}
            </button>
          {/if}
          {#if playPhase && selected.length === 1}
            <button class="btn btn-primary btn-sm" onclick={discardTile}>{t('game.discard')}</button>
          {/if}
          {#if selected.length > 0 && !taking}
            <button class="btn btn-ghost btn-sm" onclick={() => (selected = [])} aria-label={t('game.clear')}>✕</button>
          {/if}
          <div class="sort">
            <button class="btn btn-ghost btn-sm" title={t('game.sort_suit')} onclick={() => (saved = arrangeByColor(hand, COLS))}>
              <span class="swatches"><i style:background="#1f2326"></i><i style:background="#d7860b"></i><i style:background="#c8322f"></i><i style:background="#1e5bc6"></i></span>
            </button>
            <button class="btn btn-ghost btn-sm" title={t('game.sort_rank')} onclick={() => (saved = arrangeByNumber(hand, COLS))}>
              7 7 7
            </button>
          </div>
        </div>
      </div>

      <Rack
        tiles={rackTiles}
        {layout}
        cols={COLS}
        tileHeight={tileH}
        {selected}
        highlighted={[...(taking?.ids ?? []), pendingJoker ? round!.turn!.pending_joker : null]}
        ontoggle={toggle}
        onmove={moveOnRack}
      />
    </section>
  {/if}

  {#if game.phase === 'between_rounds' && game.last_result}
    <RoundResult result={game.last_result} players={table.players} totals={game.totals} atu={lastAtu} />
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
    top: 0;
    left: 0;
    width: 100%;
    height: 100vh;
    height: 100dvh;
    display: grid;
    grid-template-rows: auto 1fr auto;
    grid-template-columns: minmax(0, 1fr);
    gap: 6px;
    padding: calc(6px + var(--safe-top)) calc(8px + var(--safe-right)) calc(6px + var(--safe-bottom))
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

  .count-tiles {
    display: inline-flex;
    align-items: center;
    gap: 3px;
  }

  .count-tiles i {
    display: inline-block;
    width: 8px;
    height: 11px;
    border-radius: 2px;
    background: #f3ecdc;
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
    gap: 12px;
    min-height: 0;
  }

  .piles {
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: center;
  }

  .pile {
    position: relative;
    padding: 0;
    border: 0;
    background: none;
    border-radius: 8px;
  }

  .pile:disabled {
    cursor: default;
  }

  /* A few offset tiles suggest a pile. */
  .stack {
    filter: drop-shadow(2px 2px 0 #cfc2a6) drop-shadow(2px 2px 0 #bfb092);
  }

  .pile.active :global(.tile) {
    box-shadow:
      inset 0 -3px 0 #d8ccb2,
      0 0 0 3px var(--accent),
      0 4px 12px rgb(0 0 0 / 0.4);
  }

  .count {
    position: absolute;
    bottom: -6px;
    right: -6px;
    min-width: 22px;
    padding: 1px 5px;
    border-radius: 999px;
    background: var(--bg);
    font-size: 0.72rem;
    font-weight: 700;
  }


  .table-area {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .discards {
    display: flex;
    gap: 2px;
    overflow-x: auto;
    padding: 4px 2px 6px;
    flex: none;
    scrollbar-width: thin;
  }

  .discard {
    position: relative;
    padding: 0;
    border: 0;
    background: none;
    border-radius: 6px;
    flex: none;
  }

  .discard:disabled {
    cursor: default;
  }

  .discard.blocked {
    opacity: 0.45;
    filter: grayscale(0.6);
  }

  .discard.takeable :global(.tile) {
    box-shadow:
      inset 0 -3px 0 #d8ccb2,
      0 0 0 2px var(--accent);
  }

  .discard.in-take {
    opacity: 0.25;
  }

  .lock {
    position: absolute;
    top: -6px;
    right: -4px;
    font-size: 0.7rem;
  }

  .atu {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
  }

  .atu-label {
    font-size: 0.7rem;
    font-weight: 700;
    color: var(--accent);
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
    gap: 4px;
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
    flex: 1 1 0;
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

  .swatches {
    display: inline-flex;
    gap: 2px;
  }

  .swatches i {
    width: 7px;
    height: 12px;
    border-radius: 2px;
    border: 1px solid rgb(255 255 255 / 0.4);
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
