# Remybun — Backend Specification

Online platform for playing **Remi etalat** (Romanian card rummy).

- Backend: Elixir + Phoenix (JSON API + Phoenix Channels), Postgres via Ecto.
- Frontend: separate app (to be decided).
- Free to play. Registered accounts + guest play. Public lobby tables + private invite links.

---

## 1. Game rules

Rules are **per table**, built from a named **preset** with optional field overrides.
The rules are snapshotted into every game so history always replays under the rules it was played with.

### `Remybun.Engine.Rules`

| Field | Type | `:classic` preset | Meaning |
|---|---|---|---|
| `min_players` / `max_players` | int | 2 / 4 | Seats at the table |
| `hand_size` | int | 14 | Cards dealt; the starting player gets `hand_size + 1` and starts by discarding |
| `jokers` | int | 4 | Jokers added to 2 × 52 cards |
| `opening_min_points` | int | 45 | Minimum total value of the first lay-down |
| `discard_pickup` | `:must_use \| :free` | `:must_use` | Top discard may only be taken if used in a meld that same turn |
| `max_jokers_per_meld` | int | 1 | |
| `joker_swap` | bool | true | After opening, a player may replace a joker in a meld with the real card it represents (and must use the joker that turn) |
| `lay_off_before_opening` | bool | false | Whether adding to others' melds is allowed before opening |
| `atu` | `:off` | `:off` | Reserved for future presets |
| `joker_penalty` | int | 50 | Penalty value of a joker left in hand |
| `not_opened_penalty` | int | 100 | Flat penalty for a player who never opened |
| `joker_close_multiplier` | int | 2 | Score multiplier when going out by discarding a joker |
| `stock_exhausted` | `:reshuffle \| :end_round` | `:reshuffle` | Reshuffle the discard pile (except the top card) into the stock |
| `match` | `{:rounds, n} \| {:points_limit, n} \| :single` | `{:rounds, 4}` | Match format |
| `turn_timer_ms` | int \| nil | 60_000 | Per-turn time limit; `nil` = off |

### Classic preset — the play

- **Deck:** 2 × 52 + 4 jokers = 108 cards.
- **Turn:** draw (stock or top discard) → optionally lay down new melds / add to melds / swap jokers → discard one card.
  The starting player of a round skips the draw.
- **Melds:**
  - *Set*: 3–4 cards of the same rank, all different suits.
  - *Run*: 3+ consecutive cards of one suit. Ace is low (A-2-3) or high (Q-K-A); no wrap-around (K-A-2 is invalid).
  - At most `max_jokers_per_meld` jokers per meld; a meld can't be all jokers.
- **Card values (for opening & penalties):** 2–10 face value, J/Q/K = 10, Ace = 1 when low in a run, 11 otherwise (high run, set, or in hand).
  A joker in a meld counts as the card it stands for; in hand it is worth `joker_penalty`.
- **Opening:** the melds laid down in the turn a player first opens must total ≥ `opening_min_points`.
- **After opening:** the player may add cards to any meld on the table and swap jokers.
- **Going out:** a player goes out by discarding their last card (they must be able to discard — a player can never be left with 0 cards without discarding).
- **Round scoring (penalty points, lower is better):**
  - The player who went out scores 0.
  - Others score the sum of their hand's values, or `not_opened_penalty` if they never opened.
  - Going out by discarding a joker multiplies everyone else's penalty by `joker_close_multiplier`.
- **Stock exhausted:** reshuffle the discard pile except its top card into a new stock (or end the round with no winner under `:end_round`).
- **Match:** after `n` rounds, lowest cumulative penalty wins. The starting seat rotates each round.

---

## 2. Architecture

```
Application
├── Repo, PubSub, Presence, Endpoint
├── Registry (Remybun.Tables.Registry)
└── DynamicSupervisor (Remybun.Tables.Supervisor)
    └── Remybun.Tables.TableServer  (GenServer, one per table)
```

### Engine (`Remybun.Engine.*`) — pure functional core
No processes, no DB. Fully unit/property tested.

- `Card`, `Deck` — card representation, shuffled 108-card deck.
- `Rules` — struct, presets, validation.
- `Meld` — set/run validation, joker resolution, point values, adding cards, joker swap.
- `Round` — state machine for a single deal: `:awaiting_draw → :awaiting_discard → (next seat) … → :finished`.
  Every action is `Round.apply(round, seat, action) :: {:ok, round, [event]} | {:error, reason}`.
- `Match` — multiple rounds, cumulative scores, rotating starting seat.
- `View` — projects the full state into a per-player view (own hand visible, opponents' hands as counts only).

### Tables (`Remybun.Tables.*`)
`TableServer` holds the authoritative table state:
- Waiting room: seats, ready flags, host edits rules, host starts the game.
- In game: applies actions via the engine, broadcasts public events + per-player views.
- Turn timer: on timeout the server auto-plays (draw from stock, discard the highest-value card).
- Disconnects: seat is kept; while disconnected the player is auto-played on timeout.
- Persists games and events through `Remybun.Games`.
- Stops itself after being idle (no connected players) for a while.

---

## 3. Persistence

| Table | Columns |
|---|---|
| `users` | id, username, email (nullable for guests), hashed_password, guest (bool), timestamps |
| `users_tokens` | id, user_id, token, context, timestamps |
| `tables` | id, invite_code, visibility (`public`/`private`), host_id, rules (jsonb), status (`waiting`/`playing`/`finished`), timestamps |
| `games` | id, table_id, rules (jsonb snapshot), started_at, finished_at, winner_id |
| `game_players` | id, game_id, user_id, seat, final_score |
| `game_events` | id, game_id, seq, type, payload (jsonb), inserted_at |

Guests are `users` rows with `guest: true` and a generated username (`Guest-4821`). A guest can upgrade to a full account by setting email/password, keeping history.

---

## 4. API

### REST (JSON, `Authorization: Bearer <token>`)
| Method | Path | Description |
|---|---|---|
| POST | `/api/guest` | Create guest user → `{user, token}` |
| POST | `/api/register` | `{username, email, password}` → `{user, token}`; upgrades the current guest if authenticated as one |
| POST | `/api/login` | `{email, password}` → `{user, token}` |
| DELETE | `/api/logout` | Revoke token |
| GET | `/api/me` | Current user |
| GET | `/api/presets` | Available rule presets |
| POST | `/api/tables` | `{preset, overrides, visibility}` → table (with invite code) |
| GET | `/api/tables` | Public open tables |
| GET | `/api/tables/:invite_code` | Resolve a table by invite code |
| GET | `/api/me/games` | Game history |

### Socket: `/socket/websocket?token=<token>`

**`lobby`**
- push `tables` — list of public tables; updated with `tables_updated`.
- Presence for online users.

**`table:<table_id>`**

Client → server (reply `{:ok, ...}` or `{:error, %{reason}}`):
| Event | Payload |
|---|---|
| `sit` | `{seat}` |
| `stand` | — |
| `ready` | `{ready: bool}` |
| `update_rules` | `{preset, overrides}` (host, waiting room only) |
| `start` | — (host) |
| `draw_stock` | — |
| `take_discard` | — |
| `lay_down` | `{melds: [[card_id, ...], ...]}` |
| `add_to_meld` | `{meld_id, cards: [card_id, ...]}` |
| `swap_joker` | `{meld_id, card: card_id}` |
| `discard` | `{card: card_id}` |
| `chat` | `{text}` |

Server → client:
| Event | Payload |
|---|---|
| `state` | Full per-player snapshot (sent on join and after each change) |
| `event` | Public event (`drew_stock`, `took_discard`, `laid_down`, `discarded`, `round_finished`, …) |
| `chat` | `{user, text}` |

**Hidden information:** the server never sends another player's hand or the stock order.

---

## 5. Layout

```
remybun/
  docker-compose.yml   # Postgres for development
  docs/backend-spec.md
  backend/             # Phoenix app (no HTML/assets/LiveView)
  frontend/            # TBD
```

## 6. Milestones
1. Engine (cards, rules, melds, round, match, view) + tests.
2. Accounts: guest + registration + tokens.
3. TableServer, lobby & table channels, presence.
4. Persistence: games, players, events, history.
5. Frontend.
