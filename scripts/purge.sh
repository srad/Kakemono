#!/usr/bin/env bash
# Wrapper to run `mix kakemono.purge` inside the dev container, so it
# does not depend on the host's Elixir version.
#
# Usage:
#   ./scripts/purge.sh            # MIX_ENV=dev, prompts
#   ./scripts/purge.sh --yes      # no prompt
#   MIX_ENV=test ./scripts/purge.sh --yes
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="${KAKEMONO_MIX_CACHE:-$HOME/.cache/kakemono-mix}"
MIX_ENV="${MIX_ENV:-dev}"
IMAGE="${KAKEMONO_DEV_IMAGE:-kakemono-dev:latest}"

mkdir -p "$CACHE_DIR"

exec docker run --rm -it \
  -v "$REPO_DIR:/work" -w /work \
  -v "$CACHE_DIR:/cache" \
  -u "$(id -u):$(id -g)" \
  -e HOME=/cache -e MIX_HOME=/cache/mix -e HEX_HOME=/cache/hex \
  -e REBAR_CACHE_DIR=/cache/rebar3 \
  -e MIX_ENV="$MIX_ENV" \
  "$IMAGE" bash -lc "mix kakemono.purge $*"
