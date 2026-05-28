# Multi-stage production build for Kakemono
ARG ELIXIR_IMAGE=hexpm/elixir:1.18.2-erlang-27.3.4.8-debian-bookworm-20260518
ARG RUNTIME_IMAGE=debian:bookworm-slim

# ---- builder ----
FROM ${ELIXIR_IMAGE} AS builder

ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      git build-essential curl ca-certificates \
      libvips-dev libsqlite3-dev tzdata \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY assets assets
COPY priv priv
COPY lib lib

RUN cd assets && npm install && npm run build
RUN mix tailwind kakemono --minify
RUN mix phx.digest
RUN mix release

# ---- runtime ----
FROM ${RUNTIME_IMAGE} AS runtime

ENV LANG=C.UTF-8 \
    HOME=/app

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libstdc++6 openssl libncurses6 \
      ffmpeg libvips42 sqlite3 tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN useradd --create-home --uid 1000 kakemono && \
    mkdir -p /data && \
    chown -R kakemono:kakemono /app /data

COPY --from=builder --chown=kakemono:kakemono /app/_build/prod/rel/kakemono ./

USER kakemono

EXPOSE 4000
CMD /app/bin/kakemono eval "Kakemono.Release.migrate()" && /app/bin/kakemono start
