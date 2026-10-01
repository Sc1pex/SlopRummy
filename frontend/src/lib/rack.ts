// Layout of tiles on a player's rack: two rows of slots where tiles can sit anywhere,
// with gaps. A layout maps tile id → slot index (row-major: slot = row * cols + col).

import { sortByColor, sortByNumber } from './tiles'
import type { Tile } from './types'

export type Layout = Record<number, number>

export const RACK_ROWS = 2

/**
 * Gives every tile in `ids` a slot. Saved positions are kept when valid; tiles without one
 * fill the rack in order when the whole rack is new, otherwise they take the free slots from
 * the end of the bottom row (so a drawn tile doesn't land inside the player's groups).
 */
export function placeTiles(ids: number[], saved: Layout, slots: number): Layout {
  const layout: Layout = {}
  const taken = new Set<number>()

  for (const id of ids) {
    const slot = saved[id]
    if (slot !== undefined && slot >= 0 && slot < slots && !taken.has(slot)) {
      layout[id] = slot
      taken.add(slot)
    }
  }

  const fresh = taken.size === 0
  for (const id of ids) {
    if (layout[id] !== undefined) continue
    let slot = fresh ? 0 : slots - 1
    while (taken.has(slot)) slot += fresh ? 1 : -1
    if (slot < 0 || slot >= slots) slot = firstFree(taken, slots)
    layout[id] = slot
    taken.add(slot)
  }
  return layout
}

function firstFree(taken: Set<number>, slots: number): number {
  for (let i = 0; i < slots; i++) if (!taken.has(i)) return i
  return slots
}

/** Moves a tile to `slot`, swapping with the tile already there. */
export function moveTile(layout: Layout, id: number, slot: number): Layout {
  const from = layout[id]
  const next = { ...layout }
  const other = Object.keys(layout).find((k) => layout[Number(k)] === slot)
  if (other !== undefined) next[Number(other)] = from
  next[id] = slot
  return next
}

/**
 * Splits the selected tiles into melds by how they sit on the rack: selected tiles that are
 * next to each other in the same row form one group.
 */
export function groupsFromSelection(layout: Layout, selected: number[], cols: number): number[][] {
  const bySlot = selected
    .filter((id) => layout[id] !== undefined)
    .map((id) => ({ id, slot: layout[id] }))
    .sort((a, b) => a.slot - b.slot)

  const groups: number[][] = []
  let prev = -2
  for (const { id, slot } of bySlot) {
    const sameRow = Math.floor(slot / cols) === Math.floor(prev / cols)
    if (slot === prev + 1 && sameRow) groups[groups.length - 1].push(id)
    else groups.push([id])
    prev = slot
  }
  return groups
}

/** Lays groups out row by row with a gap between them, never splitting a group across rows. */
export function packGroups(groups: number[][], cols: number, rows = RACK_ROWS): Layout {
  const withGaps = pack(groups, cols, rows, 1)
  // Too many groups for gaps: fall back to packing tightly.
  return withGaps ?? pack(groups, cols, rows, 0) ?? pack([groups.flat()], cols, rows, 0, true)!
}

function pack(groups: number[][], cols: number, rows: number, gap: number, split = false): Layout | null {
  const layout: Layout = {}
  let row = 0
  let col = 0
  for (const group of groups) {
    if (!split && group.length > cols) return null
    if (!split && col > 0 && col + group.length > cols) {
      row++
      col = 0
    }
    for (const id of group) {
      if (split && col >= cols) {
        row++
        col = 0
      }
      if (row >= rows) return null
      layout[id] = row * cols + col++
    }
    col += gap
  }
  return layout
}

/** Groups by color, split into runs of consecutive numbers; jokers go last. */
export function arrangeByColor(tiles: Tile[], cols: number): Layout {
  const groups: number[][] = []
  let prev: Tile | null = null
  for (const t of sortByColor(tiles)) {
    const continues =
      prev && !prev.joker && !t.joker && prev.color === t.color && t.rank === prev.rank + 1
    const jokers = prev?.joker && t.joker
    if (continues || jokers) groups[groups.length - 1].push(t.id)
    else groups.push([t.id])
    prev = t
  }
  return packGroups(groups, cols)
}

/** Groups equal numbers together (possible sets); jokers go last. */
export function arrangeByNumber(tiles: Tile[], cols: number): Layout {
  const groups: number[][] = []
  let prev: Tile | null = null
  for (const t of sortByNumber(tiles)) {
    const same = prev && (prev.joker ? t.joker : !t.joker && prev.rank === t.rank)
    if (same) groups[groups.length - 1].push(t.id)
    else groups.push([t.id])
    prev = t
  }
  return packGroups(groups, cols)
}
