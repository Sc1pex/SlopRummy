import type { NumberTile, Tile, TileColor } from './types'

export const TILE_COLORS: TileColor[] = ['black', 'yellow', 'red', 'blue']

/** CSS color of a tile's number. */
export const COLOR_HEX: Record<TileColor, string> = {
  black: '#1f2326',
  yellow: '#d7860b',
  red: '#c8322f',
  blue: '#1e5bc6',
}

export function tileLabel(tile: Tile): string {
  return tile.joker ? '☺' : String(tile.rank)
}

const colorKey = (t: Tile) => (t.joker ? 99 : TILE_COLORS.indexOf(t.color))
const rankKey = (t: Tile) => (t.joker ? 99 : t.rank)

export function sortByColor(tiles: Tile[]): Tile[] {
  return [...tiles].sort((a, b) => colorKey(a) - colorKey(b) || rankKey(a) - rankKey(b) || a.id - b.id)
}

export function sortByNumber(tiles: Tile[]): Tile[] {
  return [...tiles].sort((a, b) => rankKey(a) - rankKey(b) || colorKey(a) - colorKey(b) || a.id - b.id)
}

/**
 * Value of a meld position for the opening total. Mirrors the server:
 * positions go 1..14, where 14 is a 1 placed after 13 (worth 25). Others are worth their number.
 */
export function positionValue(pos: number): number {
  return pos === 14 ? 25 : pos
}

/**
 * Points of the best valid meld made of `tiles`, or null when they don't form a meld.
 * Mirrors Remybun.Engine.Meld.build/2 so players can see their opening total before
 * laying down; the server stays the authority.
 */
export function meldPoints(tiles: Tile[], maxJokers: number): number | null {
  const candidates = [setPoints(tiles, maxJokers), runPoints(tiles, maxJokers)].filter(
    (p): p is number => p !== null,
  )
  return candidates.length ? Math.max(...candidates) : null
}

function setPoints(tiles: Tile[], maxJokers: number): number | null {
  const reals = tiles.filter((t): t is NumberTile => !t.joker)
  const jokers = tiles.length - reals.length
  if (tiles.length < 3 || tiles.length > 4 || reals.length === 0 || jokers > maxJokers) return null
  const rank = reals[0].rank
  if (reals.some((t) => t.rank !== rank)) return null
  if (new Set(reals.map((t) => t.color)).size !== reals.length) return null
  return tiles.length * positionValue(rank === 1 ? 14 : rank)
}

function runPoints(tiles: Tile[], maxJokers: number): number | null {
  const reals = tiles.filter((t): t is NumberTile => !t.joker)
  const jokers = tiles.length - reals.length
  if (reals.length === 0 || new Set(reals.map((t) => t.color)).size !== 1) return null

  // Every way to place each 1 before the 2 or after the 13.
  let placements: number[][] = [[]]
  for (const tile of reals) {
    const options = tile.rank === 1 ? [1, 14] : [tile.rank]
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
