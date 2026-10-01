# Remybun

Online Remi etalat (Romanian rummy).

- `backend/` — Elixir/Phoenix API + Channels
- `docs/backend-spec.md` — backend specification

## Development

```sh
docker compose up -d db
cd backend && mix setup && mix phx.server
```
