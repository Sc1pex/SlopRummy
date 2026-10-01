import { describe, expect, it } from 'vitest'
import { meldPoints, sortByRank, sortBySuit } from './cards'
import type { Card, Suit } from './types'

let nextId = 1
const c = (rank: number, suit: Suit): Card => ({ id: nextId++, rank, suit, joker: false })
const j = (): Card => ({ id: nextId++, joker: true })

describe('meldPoints (mirrors the server)', () => {
  it('scores sets; aces are 11', () => {
    expect(meldPoints([c(7, 'hearts'), c(7, 'spades'), c(7, 'clubs')], 1)).toBe(21)
    expect(meldPoints([c(1, 'hearts'), c(1, 'spades'), c(1, 'clubs')], 1)).toBe(33)
    expect(meldPoints([c(9, 'hearts'), j(), c(9, 'clubs')], 1)).toBe(27)
  })

  it('rejects invalid sets', () => {
    expect(meldPoints([c(7, 'hearts'), c(7, 'hearts'), c(7, 'clubs')], 1)).toBeNull()
    expect(meldPoints([c(7, 'hearts'), c(7, 'spades')], 1)).toBeNull()
  })

  it('scores runs with low and high aces, no wrap-around', () => {
    expect(meldPoints([c(6, 'hearts'), c(4, 'hearts'), c(5, 'hearts')], 1)).toBe(15)
    expect(meldPoints([c(1, 'clubs'), c(2, 'clubs'), c(3, 'clubs')], 1)).toBe(6)
    expect(meldPoints([c(12, 'clubs'), c(13, 'clubs'), c(1, 'clubs')], 1)).toBe(31)
    expect(meldPoints([c(13, 'clubs'), c(1, 'clubs'), c(2, 'clubs')], 1)).toBeNull()
  })

  it('places jokers in gaps, then high, then low', () => {
    expect(meldPoints([c(4, 'hearts'), j(), c(6, 'hearts')], 1)).toBe(15)
    expect(meldPoints([c(5, 'hearts'), c(6, 'hearts'), j()], 1)).toBe(18)
    expect(meldPoints([c(13, 'hearts'), c(1, 'hearts'), j()], 1)).toBe(31)
  })

  it('respects the joker limit and needs a real card', () => {
    expect(meldPoints([c(4, 'hearts'), j(), j()], 1)).toBeNull()
    expect(meldPoints([c(4, 'hearts'), j(), j()], 2)).toBe(15)
    expect(meldPoints([j(), j(), j()], 3)).toBeNull()
  })
})

describe('sorting', () => {
  it('sorts by suit then rank with aces high and jokers last', () => {
    const cards = [j(), c(1, 'spades'), c(2, 'hearts'), c(13, 'spades')]
    expect(sortBySuit(cards).map((x) => (x.joker ? 'J' : `${x.rank}${x.suit[0]}`))).toEqual(['13s', '1s', '2h', 'J'])
    expect(sortByRank(cards).map((x) => (x.joker ? 'J' : x.rank))).toEqual([2, 13, 1, 'J'])
  })
})
