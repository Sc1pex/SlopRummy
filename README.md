# Remybun

Online Remi etalat (Romanian rummy with tiles on racks).

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
- The rack has two rows of 16 slots. Drag tiles anywhere (gaps allowed; the layout is saved
  per table on the device) or auto-arrange by color runs / by number. Tap tiles to select them:
  selected tiles that sit next to each other form one meld, so **Lay down** sends every
  adjacent group. Tap a meld on the table to add the selected tiles (or swap a joker), select
  one tile to **Discard**.
- Production build: `npm run build` → `frontend/dist/` (static). Set `VITE_API_URL` to the backend
  origin when they are served from different hosts, and `CORS_ORIGINS` on the backend.

## Deployment (Dokploy)

`docker-compose.prod.yml` runs Postgres, the Phoenix release (migrations run on start) and an
nginx container that serves the frontend and proxies `/api` and `/socket` to the backend.

1. Dokploy → Create Service → **Compose** → Git provider → this repository, branch `main`,
   compose path `./docker-compose.prod.yml`.
2. **Environment**: `PHX_HOST`, `SECRET_KEY_BASE` (`openssl rand -base64 48`), `POSTGRES_PASSWORD`.
3. **Domains**: add the domain, service `frontend`, port `80`, HTTPS on (Let's Encrypt).
4. Deploy. Enable auto-deploy to redeploy on every push.
