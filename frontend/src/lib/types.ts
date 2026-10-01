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

export interface ScoreBreakdown {
  laid: number
  hand: number
  opened: boolean
  closing: number
  atu: number
  multiplier: number
  total: number
}

export interface RoundResult {
  winner: number | null
  double_close: boolean
  atu_multiplier: number
  scores: Record<string, number>
  breakdown: Record<string, ScoreBreakdown>
  hands: Record<string, Tile[]>
}

export type Tier = 'small' | 'big' | 'nail' | 'joker'

export interface ExchangeOffer {
  id: number
  seat: number
  tier: Tier
  /** Only on the viewer's own offers. */
  tile: Tile | null
  /** The offerer sees every answer; others only their own (with `tile`). */
  responses: { seat: number; tier: Tier; tile: Tile | null }[]
  response_count: number
}

export interface ExchangeView {
  offers: ExchangeOffer[]
  done: number[]
  can_refuse: boolean
}

export interface RoundView {
  phase: 'exchange' | 'awaiting_draw' | 'awaiting_discard' | 'finished' | 'refused'
  current: number
  starting_seat: number
  stock_count: number
  /** Oldest first; the last tile is the top. */
  discard: Tile[]
  blocked_discard: number | null
  atu: Tile
  atu_multiplier: number
  atu_announced: number[]
  atu_taken: boolean
  can_announce_atu: boolean
  /** Seats that hold 3 or fewer tiles (announced automatically). */
  last_tiles: number[]
  melds: Meld[]
  opened: Record<string, boolean>
  first_turn: Record<string, boolean>
  hand_counts: Record<string, number>
  hand: Tile[] | null
  /** Only on the viewer's own turn. */
  turn: { pending_joker: number | null; opened_now: boolean; small_hand: boolean } | null
  exchange: ExchangeView | null
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
  opening_min_points: number
  max_jokers_per_meld: number
  joker_swap: boolean
  not_opened_penalty: number
  closing_bonus: number
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
