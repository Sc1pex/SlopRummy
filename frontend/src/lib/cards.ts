import type { Card, RegularCard, Suit } from './types'

export const SUIT_SYMBOL: Record<Suit, string> = { spades: '♠', hearts: '♥', clubs: '♣', diamonds: '♦' }
const SUIT_ORDER: Suit[] = ['spades', 'hearts', 'clubs', 'diamonds']

export function rankLabel(rank: number): string {
  return ({ 1: 'A', 11: 'J', 12: 'Q', 13: 'K', 14: 'A' } as Record<number, string>)[rank] ?? String(rank)
}

export const isRed = (suit: Suit | undefined) => suit === 'hearts' || suit === 'diamonds'

export function cardLabel(card: Card): string {
  return card.joker ? '★' : `${rankLabel(card.rank)}${SUIT_SYMBOL[card.suit]}`
}

/** Aces sort high (after the King); jokers last. */
const rankKey = (c: Card) => (c.joker ? 99 : c.rank === 1 ? 14 : c.rank)
const suitKey = (c: Card) => (c.joker ? 99 : SUIT_ORDER.indexOf(c.suit))

export function sortBySuit(cards: Card[]): Card[] {
  return [...cards].sort((a, b) => suitKey(a) - suitKey(b) || rankKey(a) - rankKey(b) || a.id - b.id)
}

export function sortByRank(cards: Card[]): Card[] {
  return [...cards].sort((a, b) => rankKey(a) - rankKey(b) || suitKey(a) - suitKey(b) || a.id - b.id)
}

/** Value of a meld position: 1 is a low Ace, 14 a high Ace. Mirrors the server. */
export function positionValue(pos: number): number {
  if (pos === 1) return 1
  if (pos === 14) return 11
  return pos >= 11 ? 10 : pos
}

/**
 * Points of the best valid meld made of `cards`, or null when they don't form a meld.
 * Mirrors Remybun.Engine.Meld.build/2 so players can see their opening total before
 * laying down; the server stays the authority.
 */
export function meldPoints(cards: Card[], maxJokers: number): number | null {
  const candidates = [setPoints(cards, maxJokers), runPoints(cards, maxJokers)].filter(
    (p): p is number => p !== null,
  )
  return candidates.length ? Math.max(...candidates) : null
}

function setPoints(cards: Card[], maxJokers: number): number | null {
  const reals = cards.filter((c): c is RegularCard => !c.joker)
  const jokers = cards.length - reals.length
  if (cards.length < 3 || cards.length > 4 || reals.length === 0 || jokers > maxJokers) return null
  const rank = reals[0].rank
  if (reals.some((c) => c.rank !== rank)) return null
  if (new Set(reals.map((c) => c.suit)).size !== reals.length) return null
  return cards.length * positionValue(rank === 1 ? 14 : rank)
}

function runPoints(cards: Card[], maxJokers: number): number | null {
  const reals = cards.filter((c): c is RegularCard => !c.joker)
  const jokers = cards.length - reals.length
  if (reals.length === 0 || new Set(reals.map((c) => c.suit)).size !== 1) return null

  // Every way to place the aces low or high.
  let placements: number[][] = [[]]
  for (const card of reals) {
    const options = card.rank === 1 ? [1, 14] : [card.rank]
    placements = placements.flatMap((p) => options.filter((pos) => !p.includes(pos)).map((pos) => [...p, pos]))
  }

  let best: number | null = null
  for (const positions of placements) {
    let low = Math.min(...positions)
    let high = Math.max(...positions)
    let free = jokers - (high - low + 1 - positions.length)
    if (free < 0) continue
    while (free > 0 && high < 14) (high++, free--)
    while (free > 0 && low > 1) (low--, free--)
    const length = high - low + 1
    if (free > 0 || length < 3 || jokers > maxJokers || jokers >= length) continue

    let points = 0
    for (let pos = low; pos <= high; pos++) points += positionValue(pos)
    best = best === null ? points : Math.max(best, points)
  }
  return best
}
