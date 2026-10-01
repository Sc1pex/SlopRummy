# Remybun — Backend Specification

Online platform for playing **Remi etalat** (Romanian rummy with tiles on racks).

- Backend: Elixir + Phoenix (JSON API + Phoenix Channels), Postgres via Ecto.
- Frontend: separate app (to be decided).
- Free to play. Registered accounts + guest play. Public lobby tables + private invite links.

---

## 1. Game rules

### Table settings (`Remybun.Engine.Rules`, per table, from a preset + overrides)

| Field | `classic` | Meaning |
|---|---|---|
| `min_players` / `max_players` | 2 / 4 | Seats at the table |
| `opening_min_points` | 45 | Minimum points of the opening |
| `max_jokers_per_meld` | 1 | 1 or 2 |
| `joker_swap` | true | Opened players may swap a joker out of a meld for the tile it stands for |
| `match` | `{:rounds, 4}` | `{:rounds, n}`, `{:points_limit, n}` or `:single` |
| `turn_timer_ms` | 60_000 | Per-turn limit; `nil` = off |

Rules snapshots are stored with every game; keys that are no longer settings are ignored when loading.

### Fixed rules (implemented in `Remybun.Engine.Round`)

- **Tiles:** 1–13 in four colors (black, yellow, red, blue), two of each, + 2 jokers = 106.
- **Deal:** starting seat 15 tiles, others 14. The next tile is the **atu**: set aside, shown, out of play.
  A player dealt the atu's twin gets +50. An atu that is a 1 or a joker doubles every score of the round.
- **Duplicate exchange** (before the first discard): duplicates are two identical tiles (jokers included),
  in tiers small (2–9), big (10–13), nail (1), joker. A player offers one tile of a pair; others see only
  the tier and may answer with one of their own duplicates; the offerer accepts one answer and the two
  tiles swap. The UI warns when tiers differ. The phase ends when everyone is done or after 60s.
  A player dealt 3+ duplicate pairs may refuse the deal: everything is reshuffled and redealt.
- **Turn:** draw from the stock, or take from the discard pile → lay down / add / swap jokers → discard.
- **Discard pile:** a row in discard order. The starting player's first discard can never be taken.
  An unopened player may take only the last tile; an opened player may take any tile and gets all tiles
  after it. The chosen tile must be used immediately: `take_discard` carries the melds/additions using it.
- **First turn:** no melding of any kind on a player's first turn.
- **Opening:** at least `opening_min_points` (opening value, below) with at least one run
  and one set — or any opening containing a set of 1s. On the opening turn the player may not add to
  melds already on the table.
- **Melds:** sets of 3–4 equal numbers in different colors; runs of 3+ consecutive numbers of one color,
  a 1 before 2 or after 13, no wrap-around.
- **Opening value:** 2–9 = 5, 10–13 = 10; a 1 is 5 before a 2, 10 after 13, 25 in a set of 1s.
  A joker counts as the tile it replaces.
- **Going out:** discarding the last tile.
- **Scoring (higher is better):** tile values are 2–9 = 5, 10–13 = 10, 1 = 25. Per player: value of the
  tiles they laid (a joker as the tile it replaces) − value of tiles left in hand (joker = 50)
  + 50 for closing + 50 atu bonus.
  Then closing with a joker doubles the closer's score and a 1/joker atu doubles everyone's.
  If the stock runs out, the round ends without a closing bonus.

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
| `tables` | id, invite_code, visibility (`public`/`private`), preset, host_id, rules (jsonb), status (`waiting`/`playing`/`closed`), timestamps |
| `games` | id, table_id, rules (jsonb snapshot), status (`playing`/`finished`/`abandoned`), started_at, finished_at, winner_id |
| `game_players` | id, game_id, user_id, seat, final_score |
| `game_events` | id, game_id, seq, type, payload (jsonb), inserted_at |

`game_events` holds the public events plus server-only entries: `deal` (full deck order) and
`action` (the raw action each seat took), so games can be audited.

Tables are closed after being idle (no connections) for 5 minutes; a game in progress is marked `abandoned`.

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
- join reply `{tables}` — public tables; then pushes `table_updated` (summary) and `table_closed` (`{code}`).
- Presence for online users.

**`table:<invite_code>`** — join reply: `{state}`

Client → server (reply `{:ok, ...}` or `{:error, %{reason}}`):
| Event | Payload |
|---|---|
| `sit` | `{seat}` |
| `stand` | — |
| `ready` | `{ready: bool}` |
| `update_rules` | `{preset, overrides}` (host, waiting room only) |
| `start` | — (host) |
| `draw_stock` | — |
| `take_discard` | `{card, melds: [[card_id]], additions: [{meld_id, cards}]}` |
| `offer_duplicate` | `{card}` (exchange phase) |
| `withdraw_offer` | `{offer_id}` |
| `respond_offer` | `{offer_id, card}` |
| `withdraw_response` | `{offer_id}` |
| `accept_response` | `{offer_id, seat}` |
| `exchange_done` | — |
| `refuse_deal` | — |
| `lay_down` | `{melds: [[card_id, ...], ...]}` |
| `add_to_meld` | `{meld_id, cards: [card_id, ...]}` |
| `swap_joker` | `{meld_id, card: card_id}` |
| `discard` | `{card: card_id}` |
| `chat` | `{text}` |

Server → client:
| Event | Payload |
|---|---|
| `update` | `{events, state}` after every change. `events` are public (`round_started`, `drew_stock`, `took_discard`, `returned_discard`, `laid_down`, `added_to_meld`, `swapped_joker`, `discarded`, `turn`, `stock_reshuffled`, `round_finished`, `match_finished`, `rules_updated`); `state` is the per-player snapshot |
| `chat` | `{user_id, username, text}` |

`state` contains: `code, visibility, preset, rules, host_id, status, seats[], players[], my_seat,
game (rounds_played, totals, last_result, round{phase, current, stock_count, discard_top, melds,
opened, hand_counts, hand, must_use, result}), turn_deadline (unix ms), last_result`.
Seats in `game` and `events` are match seats, i.e. indexes into `players`.

Error replies carry `{reason}`, e.g. `not_your_turn`, `wrong_phase`, `opening_too_low`,
`must_use_discard`, `must_use_joker`, `must_keep_card_to_discard`, `invalid_meld`, `invalid_payload`.

Timers: with `turn_timer_ms` set, the server auto-plays (draw, discard highest card) on timeout.
With the timer off, a disconnected current player is auto-played after 60s.
Between rounds there is an 8s pause.

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
