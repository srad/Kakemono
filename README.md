# Kakemono

<p align="center">
  <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.18-4B275F?logo=elixir&logoColor=white">
  <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.7-FD4F00?logo=phoenixframework&logoColor=white">
  <img alt="LiveView" src="https://img.shields.io/badge/Phoenix%20LiveView-1.0-FD4F00">
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-backed-003B57?logo=sqlite&logoColor=white">
  <img alt="Docker" src="https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white">
</p>

Kakemono is a self-hosted digital signage server for small deployments: homes,
studios, shops, offices, and local dashboards. It runs on a Raspberry Pi or any
Linux host, serves display URLs for one or more screens, and gives operators a
local web control panel from a phone or laptop.

The app is built with Phoenix LiveView, SQLite, Oban, Tailwind CSS, and Vite.

## Features

- Media library for image and video uploads, including HEIC/HEVC transcoding.
- Drag-and-drop playlists for ordered media playback.
- Scene editor with dashboard grid layouts and fullscreen widget layouts.
- Widgets for clock, weather, RSS/Atom feeds, slideshows, and public Instagram posts.
- Display URLs at `/d/:display_id`, controlled from the web UI at `/c`.
- Live updates through Phoenix PubSub, so displays update without a page reload.
- Scene override through `?scene=NAME` on any display URL.
- Fully Kiosk Browser controls for wake, sleep, reload, and app restart commands.
- Built-in backups for the SQLite database and uploaded media.

Kakemono is intended for trusted local networks. Put it behind your own reverse
proxy, VPN, or access-control layer before exposing it outside a LAN.

## Project Layout

```text
assets/          Frontend JavaScript, CSS, Vite, and Vitest tests
config/          Phoenix and runtime configuration
lib/             Elixir application and web modules
priv/            Migrations, static files, and gettext files
test/            ExUnit tests and support modules
.docker/         Development container image
Dockerfile       Production release image
docker-compose.yml
```

Generated dependencies, build output, SQLite databases, uploads, backups, and
local secrets are ignored by Git.

Runtime data is consolidated under one parent directory:

```text
data/
  dev/
    kakemono_dev.db
    uploads/
    backups/
    secret.key
  test/
    kakemono_test.db
    uploads/
    backups/
```

In Docker, the same layout lives under `/data`, so one bind mount or volume is
enough for all persistent state.

## Requirements

- Elixir 1.18 and Erlang/OTP 25 or newer
- Node.js 20 or newer
- SQLite 3
- `ffmpeg`
- `libvips`

The Docker workflows include these system dependencies.

## Quick Start

```bash
mix setup
mix phx.server
```

Open:

- Control panel: <http://localhost:4000/c>
- Display view: <http://localhost:4000/d/default>

## Development Container

Build the local development image once:

```bash
./.docker/build.sh
```

Run commands inside the container:

```bash
./kdev mix setup
./kdev mix phx.server
```

The app is served at <http://localhost:4000>.

## Docker Compose

Create a local `.env` file from the example:

```bash
cp .env.example .env
mix phx.gen.secret
```

Set `SECRET_KEY_BASE` and `KAKEMONO_API_SECRET` in `.env`, then start the
release image:

```bash
docker compose up --build
```

Compose stores persistent runtime data in:

- `./data/kakemono.db` for SQLite
- `./data/uploads` for uploaded media
- `./data/backups` for backup archives
- `./data/secret.key` for the regenerated API secret

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `4000` | HTTP port |
| `PHX_HOST` | `example.com` in production | Host used for generated URLs |
| `SECRET_KEY_BASE` | required in production | Phoenix signing/encryption secret |
| `KAKEMONO_DATA_DIR` | `data/dev`, `data/test`, or `/data` in production | Parent directory for all runtime data |
| `DATABASE_PATH` | `<data-dir>/kakemono_<env>.db` or `<data-dir>/kakemono.db` in production | SQLite database path |
| `KAKEMONO_API_SECRET` | `dev-secret-change-me` | Shared secret for display API calls |
| `KAKEMONO_API_SECRET_FILE` | `<data-dir>/secret.key` | Persisted API secret path |
| `KAKEMONO_UPLOADS_DIR` | `<data-dir>/uploads` | Uploaded media directory |
| `KAKEMONO_BACKUPS_DIR` | `<data-dir>/backups` | Backup archive directory |

`DATABASE_PATH`, `KAKEMONO_UPLOADS_DIR`, `KAKEMONO_BACKUPS_DIR`, and
`KAKEMONO_API_SECRET_FILE` are advanced overrides. For normal deployments, set
only `KAKEMONO_DATA_DIR`.

The API secret can also be regenerated from `/c/settings`. The generated value
is stored in `<data-dir>/secret.key`, which is ignored by Git and persisted by
the Docker data volume. When that file exists, it is loaded on startup.

## Backups

Create a zip archive containing the database and uploaded media:

```bash
mix kakemono.backup
```

Reset local development data:

```bash
mix kakemono.purge
mix kakemono.purge --yes
```

## Tests

```bash
mix test
cd assets && npm test
```

## Updating Dependencies

Update Elixir dependencies:

```bash
mix hex.outdated
mix deps.update --all
mix test
```

Update a single Elixir dependency:

```bash
mix deps.update phoenix
```

For major Elixir upgrades, update the version constraint in `mix.exs`, run
`mix deps.get`, then rerun the test suite.

Update frontend dependencies:

```bash
cd assets
npm outdated
npm update
npm test
npm run build
```

For major frontend upgrades, install the explicit latest package version:

```bash
cd assets
npm install package-name@latest
```

Update Docker base images by changing the image tags in `Dockerfile` and
`.docker/Dockerfile.dev`, then rebuild:

```bash
docker compose build --pull
./.docker/build.sh
```

After dependency updates, run the full verification pass:

```bash
mix format
mix test
cd assets && npm test && npm run build
```
