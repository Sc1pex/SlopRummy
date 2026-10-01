// Shapes of the data sent by the backend (see docs/backend-spec.md).
// Maps keyed by seat arrive with string keys ("0", "1", ...).

export type TileColor = 'black' | 'yellow' | 'red' | 'blue'

export interface NumberTile {
  id: number
  rank: number // 1..13
  color: TileColor
  joker: false
}

export interface JokerTile {
  id: number
  joker: true
  /** Only on jokers inside a meld: what the joker stands for. */
  as?: { rank: number; color?: TileColor }
}

export type Tile = NumberTile | JokerTile

export interface User {
  id: number
  username: string
  email: string | null
  guest: boolean
}

export interface Meld {
  id: number
  owner: number
  type: 'set' | 'run'
  rank: number | null
  color: TileColor | null
  cards: Tile[]
  points: number
}

export interface RoundResult {
  winner: number | null
  joker_close: boolean
  scores: Record<string, number>
  hands: Record<string, Tile[]>
}

export interface RoundView {
  phase: 'awaiting_draw' | 'awaiting_discard' | 'finished'
  current: number
  starting_seat: number
  stock_count: number
  discard_top: Tile | null
  discard_count: number
  melds: Meld[]
  opened: Record<string, boolean>
  hand_counts: Record<string, number>
  hand: Tile[] | null
  must_use: { taken_discard: number | null; pending_joker: number | null } | null
  result: RoundResult | null
}

export interface GameView {
  phase: 'between_rounds' | 'playing' | 'finished'
  rounds_played: number
  totals: Record<string, number>
  winners: number[]
  last_result: RoundResult | null
  round: RoundView | null
}

export interface Player {
  seat: number
  id: number
  username: string
  connected: boolean
}

export interface Seat {
  seat: number
  user: { id: number; username: string; connected: boolean } | null
  ready: boolean
}

export type MatchFormat = { type: 'rounds' | 'points_limit'; n: number } | { type: 'single' }

export interface Rules {
  min_players: number
  max_players: number
  hand_size: number
  jokers: number
  opening_min_points: number
  discard_pickup: 'must_use' | 'free'
  max_jokers_per_meld: number
  joker_swap: boolean
  lay_off_before_opening: boolean
  atu: 'off'
  joker_penalty: number
  not_opened_penalty: number
  joker_close_multiplier: number
  stock_exhausted: 'reshuffle' | 'end_round'
  match: MatchFormat
  turn_timer_ms: number | null
}

export interface MatchResult {
  totals: Record<string, number>
  winners: number[]
  players: { user_id: number; username: string }[]
  rounds: RoundResult[]
}

export interface TableState {
  code: string
  visibility: 'public' | 'private'
  preset: string
  rules: Rules
  host_id: number
  status: 'waiting' | 'playing'
  seats: Seat[]
  players: Player[]
  my_seat: number | null
  game: GameView | null
  turn_deadline: number | null
  last_result: MatchResult | null
}

export interface GameEvent {
  type: string
  seat?: number
  card?: Tile
  [key: string]: unknown
}

export interface TableSummary {
  code: string
  visibility: 'public' | 'private'
  preset: string
  status: 'waiting' | 'playing'
  host_id: number
  max_players: number
  min_players: number
  players: { id: number; username: string }[]
  created_at: string
}

export interface ChatMessage {
  user_id: number
  username: string
  text: string
}

export interface Preset {
  name: string
  description: string
  rules: Rules
}

export interface HistoryGame {
  id: number
  status: 'finished' | 'abandoned'
  started_at: string
  finished_at: string | null
  winner_id: number | null
  players: { seat: number; user_id: number | null; username: string | null; final_score: number | null }[]
}
