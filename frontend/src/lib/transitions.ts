import { crossfade, scale } from 'svelte/transition'
import { cubicOut } from 'svelte/easing'

/**
 * Shared crossfade keyed by card id: a card leaving the hand flies to wherever a card
 * with the same id appears (discard pile, a meld) and vice versa.
 */
export const [send, receive] = crossfade({
  duration: 320,
  easing: cubicOut,
  fallback: (node) => scale(node, { start: 0.6, duration: 200 }),
})
