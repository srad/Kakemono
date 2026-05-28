# Kakemono

<p align="center">
  <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.18-4B275F?logo=elixir&logoColor=white">
  <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white">
  <img alt="LiveView" src="https://img.shields.io/badge/Phoenix%20LiveView-1.1-FD4F00">
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
assets/          Frontend build (Vite/esbuild), global CSS, shared JS hooks, Vitest tests
config/          Phoenix and runtime configuration
lib/             Elixir application and web modules; each widget co-locates its
                 module, CSS, and JS hook under lib/kakemono/widgets/<name>/
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
- Node.js 22 or newer (Vite 8 requires Node 20.19+ or 22.12+)
- SQLite 3
- `ffmpeg`
- `libvips`

The Docker workflows include these system dependencies.

## Development Environment Setup

Elixir and Erlang are pinned with [asdf](https://asdf-vm.com); the exact
versions live in the `.tool-versions` file at the repository root.

### Automated setup (Ubuntu)

On Ubuntu (or another Debian-based host), run the `setup-erlang.sh` helper
script from the repository root. It installs build dependencies, asdf, the
pinned Erlang/Elixir versions from `.tool-versions`, and compiles the project:

```bash
./setup-erlang.sh
```

When it finishes, open a new terminal (or `source ~/.bashrc`) so asdf is on your
`PATH`, then start the server:

```bash
mix phx.server
```

### Manual setup with asdf

If you already have asdf installed, add the plugins and install the versions
from `.tool-versions`:

```bash
asdf plugin add erlang
asdf plugin add elixir
asdf install
```

`asdf install` reads `.tool-versions` and installs the listed versions.
Building Erlang from source needs the usual build toolchain (for example
`build-essential`, `autoconf`, `m4`, `libssl-dev`, `libncurses-dev`); see
`setup-erlang.sh` for the full package list.

Verify the toolchain is active in the project directory:

```bash
elixir --version
```

asdf must be sourced in your shell for `mix`, `iex`, and `erl` to resolve. Most
shells load it automatically; in non-interactive shells source it explicitly:

```bash
. "$HOME/.asdf/asdf.sh"
```

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

## Adding a Widget

A widget is a self-describing module that does `use Kakemono.Widget`
(`lib/kakemono/widget.ex`). It is **auto-discovered** — there is no registry list
to edit. All of a widget's files are co-located in one folder:

```text
lib/kakemono/widgets/<name>/
  <name>.ex     Widget module (use Kakemono.Widget)
  <name>.css    Optional styles (omit if the widget needs none)
  <name>.js     Optional LiveView JS hook
```

1. **Implement the module.** Create `lib/kakemono/widgets/<name>/<name>.ex`:

   ```elixir
   defmodule Kakemono.Widgets.Foo do
     use Kakemono.Widget

     @impl true
     def type, do: "foo"
     @impl true
     def name, do: "Foo"
     @impl true
     def icon, do: "✨"
     @impl true
     def fields do
       [%{key: "label", label: "Label", type: :text, required: true, default: "Foo"}]
     end
     @impl true
     def render(assigns), do: ~H"<div class=\"kakemono-widget\">{@instance.config[\"label\"]}</div>"
   end
   ```

   Only `type/0`, `name/0`, and `render/1` are required. The `fields/0` list is the
   **single source of config truth**: the JSON Schema (`config_schema/0`), the
   defaults (`default_config/0`), and the scene-editor form are all derived from it
   (see `Kakemono.Widget.Config`). `icon/0` supplies the picker glyph. Use an
   existing widget such as `lib/kakemono/widgets/clock/clock.ex` as a template.

2. **Add styles (optional).** Put `<name>.css` in the widget folder, wrap rules in
   `@layer components { … }`, and import it from `assets/css/app.css`:

   ```css
   @import "../../lib/kakemono/widgets/<name>/<name>.css";
   ```

3. **Add a JS hook (optional).** Put `<name>.js` in the widget folder, import it in
   `assets/js/app.js`, and add it to the `Hooks` map.

4. **Add remote data (optional).** Implement `fetch/1` (returns `{:ok, patch}` to
   cache, `:skip`, or `{:error, reason}`) and list the cached keys in
   `cache_fields/0` so they pass schema validation. Implement `prefetch/1` to fetch
   lazily on first display mount and `on_config_change/2` to refetch when a source
   field changes. The generic `Kakemono.Widgets.FetchWorker` runs `fetch/1`; add the
   widget's `type` to a `RefreshScheduler` line in `config/config.exs` to refresh it
   on a cron cadence. See the `weather` or `rss` widgets for the pattern.

Run `mix compile && mix assets.build` and the new widget appears in the scene
editor's widget picker.

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
