# Kakemono

<p align="center">
  <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.18-4B275F?logo=elixir&logoColor=white">
  <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white">
  <img alt="LiveView" src="https://img.shields.io/badge/Phoenix%20LiveView-1.1-FD4F00">
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-backed-003B57?logo=sqlite&logoColor=white">
  <a href="https://hub.docker.com/r/sedrad/kakemono"><img alt="Docker image sedrad/kakemono" src="https://img.shields.io/badge/Docker-sedrad%2Fkakemono-2496ED?logo=docker&logoColor=white"></a>
</p>

Self-hosted digital signage server for small deployments — homes, studios, shops,
offices, dashboards. Runs on a Raspberry Pi or any Linux host, serves display URLs
for one or more screens, and gives operators a web control panel from a phone or
laptop. Built with Phoenix LiveView, SQLite, Oban, and Tailwind CSS.

## Features

- Media library for image/video uploads with HEIC/HEVC transcoding.
- Drag-and-drop playlists and a scene editor (dashboard grids and fullscreen layouts).
- Widgets: clock, weather, RSS/Atom feeds, slideshows, public Instagram posts.
- Public display URLs at `/d/:display_id`; password-protected control panel at `/c`.
- Live updates via Phoenix PubSub — displays refresh without a page reload.
- Scene override with `?scene=NAME` on any display URL.
- Kiosk Browser controls (wake, sleep, reload, restart) and built-in DB + media backups.

## Requirements

- Elixir 1.18 and Erlang/OTP 25+ (pinned in `.tool-versions`)
- Node.js 22+ (Vite 8 needs Node 20.19+ or 22.12+)
- SQLite 3, `ffmpeg`, `libvips`

The Docker workflows bundle the system dependencies.

## Setup

Elixir/Erlang are pinned with [asdf](https://asdf-vm.com). On Debian/Ubuntu, the
helper script installs build deps, asdf, the pinned versions, and compiles:

```bash
./setup-erlang.sh
```

With asdf already installed, run `asdf install` (reads `.tool-versions`). asdf must
be on your shell `PATH`; in non-interactive shells source it explicitly:

```bash
. "$HOME/.asdf/asdf.sh"
```

## Quick start (development)

```bash
mix setup
mix phx.server
```

- Control panel: <http://localhost:4000/c>
- Display view: <http://localhost:4000/d/default>

On first visit to `/c` you are redirected to `/login`. In development you set the
backend password there (the gate protects `/c` and the landing page `/`; display
URLs stay public). The password must be at least 12 characters.

## Production deployment

Production **fails closed** — the app refuses to boot until secrets are provisioned.
Set these (or provide the persisted files noted in the table below):

```bash
SECRET_KEY_BASE=$(mix phx.gen.secret)   # required
KAKEMONO_API_SECRET=<long random value> # required — displays authenticate with it
KAKEMONO_BACKEND_PASSWORD=<≥12 chars>    # required — seeds the backend password on boot
PHX_HOST=signage.example.com            # your real hostname
```

Run **behind an HTTPS-terminating reverse proxy.** In production the app forces SSL,
emits HSTS, marks the session cookie `Secure`, and restricts the LiveView websocket
origin to `https://$PHX_HOST`. The proxy must terminate TLS and forward
`X-Forwarded-Proto`. Anonymous web password setup is disabled in production, so the
backend password can only come from `KAKEMONO_BACKEND_PASSWORD` or an existing hash
file. Change it later from `/c/settings`.

## Docker

Local development image:

```bash
./.docker/build.sh
./kdev mix setup
./kdev mix phx.server
```

Docker Compose (published release image):

```yaml
services:
  app:
    image: sedrad/kakemono:latest
    container_name: kakemono
    restart: unless-stopped
    ports:
      - "${PORT:-4000}:${PORT:-4000}"
    environment:
      KAKEMONO_DATA_DIR: ${KAKEMONO_DATA_DIR:-/data}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:?set SECRET_KEY_BASE in .env}
      KAKEMONO_API_SECRET: ${KAKEMONO_API_SECRET:?set KAKEMONO_API_SECRET in .env}
      KAKEMONO_BACKEND_PASSWORD: ${KAKEMONO_BACKEND_PASSWORD:?set KAKEMONO_BACKEND_PASSWORD in .env}
      PHX_HOST: ${PHX_HOST:-localhost}
      PHX_SERVER: "true"
      PORT: ${PORT:-4000}
    volumes:
      - ./data:/data
```

Example `.env` values:

```env
PORT=4000
PHX_HOST=signage.example.com
SECRET_KEY_BASE=replace-with-output-from-mix-phx.gen.secret
KAKEMONO_API_SECRET=replace-with-a-long-random-secret
KAKEMONO_BACKEND_PASSWORD=replace-with-a-strong-password-min-12-chars
KAKEMONO_DATA_DIR=/data
```

Docker Compose with Traefik 3.7 TLS proxy:

```yaml
services:
  traefik:
    image: traefik:v3.7
    container_name: traefik
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      # Only needed if Traefik itself is behind another trusted proxy:
      # - "--entrypoints.websecure.forwardedHeaders.trustedIPs=${TRAEFIK_TRUSTED_IPS}"
      - "--certificatesresolvers.letsencrypt.acme.email=${TRAEFIK_ACME_EMAIL:?set TRAEFIK_ACME_EMAIL in .env}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik-letsencrypt:/letsencrypt

  app:
    image: sedrad/kakemono:latest
    container_name: kakemono
    restart: unless-stopped
    environment:
      KAKEMONO_DATA_DIR: ${KAKEMONO_DATA_DIR:-/data}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:?set SECRET_KEY_BASE in .env}
      KAKEMONO_API_SECRET: ${KAKEMONO_API_SECRET:?set KAKEMONO_API_SECRET in .env}
      KAKEMONO_BACKEND_PASSWORD: ${KAKEMONO_BACKEND_PASSWORD:?set KAKEMONO_BACKEND_PASSWORD in .env}
      PHX_HOST: ${PHX_HOST:?set PHX_HOST in .env}
      PHX_SERVER: "true"
      PORT: "4000"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kakemono.rule=Host(`${PHX_HOST:?set PHX_HOST in .env}`)"
      - "traefik.http.routers.kakemono.entrypoints=websecure"
      - "traefik.http.routers.kakemono.tls.certresolver=letsencrypt"
      - "traefik.http.services.kakemono.loadbalancer.server.port=4000"
      - "traefik.http.middlewares.kakemono-forwarded-proto.headers.customrequestheaders.X-Forwarded-Proto=https"
      - "traefik.http.routers.kakemono.middlewares=kakemono-forwarded-proto"
    volumes:
      - ./data:/data

volumes:
  traefik-letsencrypt:
```

Additional `.env` values for Traefik:

```env
TRAEFIK_ACME_EMAIL=admin@example.com
TRAEFIK_TRUSTED_IPS=203.0.113.10/32
```

`TRAEFIK_TRUSTED_IPS` is only needed when you uncomment the
`forwardedHeaders.trustedIPs` line because Traefik is behind another trusted
proxy.

Traefik forwards `X-Forwarded-*` request headers to the container by default; the
middleware above makes `X-Forwarded-Proto: https` explicit for Phoenix SSL
rewrite handling after TLS termination.

```bash
cp .env.example .env          # fill in the secrets below
docker compose up -d
```

Set `SECRET_KEY_BASE`, `KAKEMONO_API_SECRET`, and `KAKEMONO_BACKEND_PASSWORD` in
`.env`. Persistent state lives under `/data` (one bind mount/volume): `kakemono.db`,
`uploads/`, `backups/`, `secret.key`, and `backend_password.hash`.

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `4000` | HTTP port |
| `PHX_HOST` | `example.com` (prod) | Host for generated URLs and websocket origin check |
| `SECRET_KEY_BASE` | required (prod) | Phoenix signing/encryption secret |
| `KAKEMONO_API_SECRET` | `dev-secret-change-me` (dev) | Shared `x-kakemono-secret` for display API calls; required in prod unless the secret file exists |
| `KAKEMONO_BACKEND_PASSWORD` | — | Backend login password (≥12 chars); required in prod unless the hash file exists |
| `KAKEMONO_DATA_DIR` | `data/dev`, `data/test`, or `/data` (prod) | Parent directory for all runtime data |

Advanced overrides (default under the data dir): `DATABASE_PATH`,
`KAKEMONO_UPLOADS_DIR`, `KAKEMONO_BACKUPS_DIR`, `KAKEMONO_API_SECRET_FILE`,
`KAKEMONO_BACKEND_PASSWORD_FILE`. For normal deployments set only `KAKEMONO_DATA_DIR`.

The API secret can also be regenerated from `/c/settings`; it persists to
`<data-dir>/secret.key` and is loaded on startup when present.

## Project layout

```text
assets/      Frontend build (Vite/esbuild), CSS, JS hooks, Vitest tests
config/      Phoenix and runtime configuration
lib/         App and web modules; each widget co-locates module + CSS + JS hook
             under lib/kakemono/widgets/<name>/
priv/        Migrations, static files, gettext
test/        ExUnit tests and support
Dockerfile, docker-compose.yml, .docker/   Container images
```

Runtime data (DB, uploads, backups, secret/password files) lives under the data dir
and is ignored by Git.

## License

Kakemono is source-available under the
[PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)
(`PolyForm-Noncommercial-1.0.0`) for free non-commercial use.

The license permits personal, private, educational institution, research,
charitable or nonprofit, community, and similar non-commercial use. Commercial
use is not covered by this license and requires a separate paid commercial
license from the copyright holder.

See [`LICENSE`](LICENSE) for the full terms.

## Maintenance

```bash
mix test                       # Elixir suite
cd assets && npm test          # frontend suite
mix kakemono.backup            # zip of DB + uploaded media
mix kakemono.purge --yes       # reset local dev data
```

Dependency updates:

```bash
mix hex.outdated && mix deps.update --all && mix test
cd assets && npm outdated && npm update && npm test && npm run build
```

For major bumps, pin the new version (`mix.exs` constraint or `npm install pkg@latest`)
and rerun the suites. Update Docker base images by editing the tags in `Dockerfile` /
`.docker/Dockerfile.dev` and rebuilding with `--pull`. Full verification pass:

```bash
mix format && mix test && cd assets && npm test && npm run build
```

## Adding a widget

A widget is a self-describing module using `use Kakemono.Widget`
(`lib/kakemono/widget.ex`). Widgets are **auto-discovered** — no registry to edit.
Co-locate all files in one folder:

```text
lib/kakemono/widgets/<name>/
  <name>.ex     Widget module (use Kakemono.Widget)
  <name>.css    Optional styles
  <name>.js     Optional LiveView JS hook
```

1. **Implement the module.** Only `type/0`, `name/0`, and `render/1` are required.
   `fields/0` is the single source of config truth — the JSON Schema, defaults, and
   scene-editor form all derive from it (see `Kakemono.Widget.Config`); `icon/0`
   supplies the picker glyph. Use `lib/kakemono/widgets/clock/clock.ex` as a template.
2. **Styles (optional).** Add `<name>.css`, wrap rules in `@layer components { … }`,
   and `@import` it from `assets/css/app.css`.
3. **JS hook (optional).** Add `<name>.js`, import it in `assets/js/app.js`, and add it
   to the `Hooks` map.
4. **Remote data (optional).** Implement `fetch/1` (`{:ok, patch}` | `:skip` |
   `{:error, reason}`) and list cached keys in `cache_fields/0`; add `prefetch/1` and
   `on_config_change/2` as needed. `Kakemono.Widgets.FetchWorker` runs `fetch/1`; add
   the widget `type` to a `RefreshScheduler` cron line in `config/config.exs` to refresh
   on a cadence. See the `weather` or `rss` widgets.

Run `mix compile && mix assets.build`; the widget appears in the scene editor's picker.
