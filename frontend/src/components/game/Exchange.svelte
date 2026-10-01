<script lang="ts">
  import { t } from '../../lib/i18n.svelte'
  import type { Player, RoundView, Tier, Tile as TileT } from '../../lib/types'
  import Tile from '../Tile.svelte'

  interface Props {
    round: RoundView
    players: Player[]
    mySeat: number | null
    act: (event: string, payload?: Record<string, unknown>) => Promise<boolean>
  }

  let { round, players, mySeat, act }: Props = $props()

  const exchange = $derived(round.exchange!)
  const done = $derived(mySeat !== null && exchange.done.includes(mySeat))
  const nameOf = (seat: number) => players[seat]?.username ?? '?'
  const tierName = (tier: Tier) => t(`tier.${tier}`)

  function tierOf(tile: TileT): Tier {
    if (tile.joker) return 'joker'
    if (tile.rank === 1) return 'nail'
    return tile.rank >= 10 ? 'big' : 'small'
  }

  const keyOf = (tile: TileT) => (tile.joker ? 'J' : `${tile.rank}-${tile.color}`)

  // My duplicate pairs (two identical tiles; jokers included).
  const pairs = $derived.by(() => {
    const byKey = new Map<string, TileT[]>()
    for (const tile of round.hand ?? []) byKey.set(keyOf(tile), [...(byKey.get(keyOf(tile)) ?? []), tile])
    return [...byKey.values()].filter((tiles) => tiles.length >= 2).map((tiles) => tiles.slice(0, 2))
  })

  const myOffers = $derived(exchange.offers.filter((o) => o.seat === mySeat))
  const otherOffers = $derived(exchange.offers.filter((o) => o.seat !== mySeat))

  /** The offer or answer a pair is currently committed to, if any. */
  function commitmentOf(pair: TileT[]) {
    const key = keyOf(pair[0])
    const offer = myOffers.find((o) => o.tile && keyOf(o.tile) === key)
    if (offer) return { kind: 'offer' as const, offer }
    const answered = otherOffers.find((o) => o.responses.some((r) => r.seat === mySeat && r.tile && keyOf(r.tile) === key))
    if (answered) return { kind: 'answer' as const, offer: answered }
    return null
  }

  const freePairs = $derived(pairs.filter((p) => !commitmentOf(p)))

  // Which offer the picker is open for.
  let picking = $state<number | null>(null)

  async function respond(offerId: number, offerTier: Tier, tile: TileT) {
    const give = tierOf(tile)
    if (give !== offerTier && !confirm(t('exchange.warn_respond', { give: tierName(give), get: tierName(offerTier) })))
      return
    if (await act('respond_offer', { offer_id: offerId, card: tile.id })) picking = null
  }

  function accept(offerId: number, myTier: Tier, seat: number, theirTier: Tier) {
    if (myTier !== theirTier && !confirm(t('exchange.warn_accept', { give: tierName(myTier), get: tierName(theirTier) })))
      return
    act('accept_response', { offer_id: offerId, seat })
  }

  function refuse() {
    if (confirm(t('exchange.refuse_confirm'))) act('refuse_deal')
  }
</script>

<section class="exchange panel" style:--tile-h="44px">
  <header>
    <div>
      <h2>{t('exchange.title')}</h2>
      <p class="muted">{t('exchange.hint')}</p>
    </div>
    <div class="atu">
      <span class="muted">{t('game.atu')}</span>
      <Tile tile={round.atu} />
    </div>
  </header>

  <div class="columns">
    {#if mySeat !== null}
      <div class="col">
        <h3>{t('exchange.yours')}</h3>
        {#if pairs.length === 0}
          <p class="muted small">{t('exchange.none')}</p>
        {/if}
        {#each pairs as pair (keyOf(pair[0]))}
          {@const commitment = commitmentOf(pair)}
          <div class="row">
            <div class="pair"><Tile tile={pair[0]} /><Tile tile={pair[1]} /></div>
            <div class="info">
              <div class="tier">{tierName(tierOf(pair[0]))}</div>
              {#if commitment?.kind === 'offer'}
                {@const offer = commitment.offer}
                <div class="small muted">{t('exchange.offered')}</div>
                {#each offer.responses as answer (answer.seat)}
                  <div class="answer">
                    <span>{t('exchange.answer_from', { name: nameOf(answer.seat), tier: tierName(answer.tier) })}</span>
                    <button class="btn btn-primary btn-sm" onclick={() => accept(offer.id, offer.tier, answer.seat, answer.tier)}>
                      {t('exchange.accept')}
                    </button>
                  </div>
                {:else}
                  <div class="small muted">{t('exchange.no_answers')}</div>
                {/each}
              {:else if commitment?.kind === 'answer'}
                <div class="small muted">{t('exchange.proposed_to', { name: nameOf(commitment.offer.seat) })}</div>
              {/if}
            </div>
            <div class="actions">
              {#if commitment?.kind === 'offer'}
                <button class="btn btn-ghost btn-sm" onclick={() => act('withdraw_offer', { offer_id: commitment.offer.id })}>
                  {t('exchange.withdraw')}
                </button>
              {:else if commitment?.kind === 'answer'}
                <button class="btn btn-ghost btn-sm" onclick={() => act('withdraw_response', { offer_id: commitment.offer.id })}>
                  {t('exchange.withdraw')}
                </button>
              {:else}
                <button class="btn btn-sm" disabled={done} onclick={() => act('offer_duplicate', { card: pair[0].id })}>
                  {t('exchange.offer')}
                </button>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}

    <div class="col">
      <h3>{t('exchange.others')}</h3>
      {#if otherOffers.length === 0}
        <p class="muted small">{t('exchange.no_offers')}</p>
      {/if}
      {#each otherOffers as offer (offer.id)}
        {@const mine = offer.responses.find((r) => r.seat === mySeat)}
        <div class="row">
          <div class="info">
            <div class="tier">{t('exchange.offers_tier', { name: nameOf(offer.seat), tier: tierName(offer.tier) })}</div>
            {#if mine?.tile}
              <div class="small muted proposed">{t('exchange.you_proposed')} <Tile tile={mine.tile} /></div>
            {/if}
            {#if picking === offer.id}
              <div class="small">{t('exchange.pick')}</div>
              <div class="choices">
                {#each freePairs as pair (keyOf(pair[0]))}
                  <button
                    class="choice"
                    class:mismatch={tierOf(pair[0]) !== offer.tier}
                    onclick={() => respond(offer.id, offer.tier, pair[0])}
                    aria-label={tierName(tierOf(pair[0]))}
                  >
                    <Tile tile={pair[0]} />
                  </button>
                {/each}
              </div>
            {/if}
          </div>
          {#if mySeat !== null}
            <div class="actions">
              {#if mine}
                <button class="btn btn-ghost btn-sm" onclick={() => act('withdraw_response', { offer_id: offer.id })}>
                  {t('exchange.withdraw')}
                </button>
              {:else if picking === offer.id}
                <button class="btn btn-ghost btn-sm" onclick={() => (picking = null)}>✕</button>
              {:else}
                <button class="btn btn-sm" disabled={done || freePairs.length === 0} onclick={() => (picking = offer.id)}>
                  {t('exchange.propose')}
                </button>
              {/if}
            </div>
          {/if}
        </div>
      {/each}
    </div>
  </div>

  {#if round.atu_announced.length}
    <p class="small muted">
      {round.atu_announced.map((s) => t('exchange.atu_announced', { name: nameOf(s) })).join(' · ')}
    </p>
  {/if}

  {#if mySeat !== null}
    <footer>
      <span class="muted small">{t('exchange.waiting', { done: exchange.done.length, total: players.length })}</span>
      {#if round.can_announce_atu}
        <button class="btn btn-sm" onclick={() => act('announce_atu')}>{t('exchange.announce_atu')}</button>
      {/if}
      {#if exchange.can_refuse}
        <button class="btn btn-sm btn-danger" onclick={refuse}>{t('exchange.refuse')}</button>
      {/if}
      <button class="btn btn-primary btn-sm" disabled={done} onclick={() => act('exchange_done')}>{t('exchange.done')}</button>
    </footer>
  {/if}
</section>

<style>
  .exchange {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 10px 12px;
    overflow-y: auto;
    background: rgb(11 21 18 / 0.92);
  }

  header {
    display: flex;
    justify-content: space-between;
    gap: 12px;
  }

  h2 {
    font-size: 1rem;
  }

  h3 {
    font-size: 0.85rem;
    margin-bottom: 4px;
    color: var(--muted);
  }

  header p {
    margin: 2px 0 0;
    font-size: 0.8rem;
  }

  .atu {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.8rem;
  }

  .columns {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    gap: 12px;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 0;
    border-top: 1px solid var(--border);
  }

  .pair {
    display: flex;
    gap: 2px;
  }

  .info {
    flex: 1;
    min-width: 0;
  }

  .tier {
    font-weight: 700;
    font-size: 0.85rem;
  }

  .small {
    font-size: 0.78rem;
  }

  .answer {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 4px;
    font-size: 0.8rem;
  }

  .proposed {
    display: flex;
    align-items: center;
    gap: 6px;
    --tile-h: 30px;
  }

  .choices {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-top: 4px;
  }

  .choice {
    padding: 2px;
    border: 2px solid transparent;
    border-radius: 8px;
    background: none;
  }

  .choice.mismatch {
    border-color: color-mix(in srgb, var(--danger) 60%, transparent);
  }

  footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
    margin-top: auto;
    padding-top: 6px;
  }

  footer .muted {
    margin-right: auto;
  }
</style>
