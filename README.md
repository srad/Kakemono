# Kakemono

<p align="center">
  <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.18-4B275F?logo=elixir&logoColor=white">
  <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white">
  <img alt="LiveView" src="https://img.shields.io/badge/Phoenix%20LiveView-1.1-FD4F00">
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-backed-003B57?logo=sqlite&logoColor=white">
  <img alt="Docker" src="https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white">
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

Docker Compose (production release image):

```bash
cp .env.example .env          # fill in the secrets below
docker compose up --build
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
