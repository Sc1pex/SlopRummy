# Remybun

Online Remi etalat (Romanian rummy).

- `backend/` — Elixir/Phoenix JSON API + Channels ([spec](docs/backend-spec.md))
- `frontend/` — Svelte 5 + Vite + TypeScript, installable PWA

## Development

```sh
docker compose up -d db                       # Postgres
cd backend && mix setup && mix phx.server     # API on :4000
cd frontend && npm install && npm run dev     # app on :5173 (proxies /api and /socket to :4000)
```

Open http://localhost:5173. To try the phone layout from a real device on the same network,
run `npm run dev -- --host` and open the printed network URL.

Tests: `cd backend && mix test`, `cd frontend && npm test && npm run check`.

## Frontend notes

- Lobby, login and history are portrait-first; the game screen is landscape.
- On touch devices, tapping **Ready** / **Start** (or "Tap to enter the game" after a reload)
  requests fullscreen and locks landscape. iPhone Safari supports neither: players get a
  "rotate your phone" overlay, and installing the PWA (Share → Add to Home Screen) removes the
  browser bars.
- Cards: tap to select, drag sideways to reorder (order is saved per table on the device),
  **Group** stages a meld, **Lay down** sends all staged melds, tap a table meld to add the
  selected cards (or swap a joker), select one card to **Discard**.
- Production build: `npm run build` → `frontend/dist/` (static). Set `VITE_API_URL` to the backend
  origin when they are served from different hosts, and `CORS_ORIGINS` on the backend.
