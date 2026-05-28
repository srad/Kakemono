# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kakemono,
  ecto_repos: [Kakemono.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :kakemono, KakemonoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KakemonoWeb.ErrorHTML, json: KakemonoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kakemono.PubSub,
  live_view: [signing_salt: "hM8LKfJ/"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :kakemono, Kakemono.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.28.0",
  kakemono: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  kakemono: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :mime, :types, %{
  "image/heic" => ["heic"],
  "image/heif" => ["heif"],
  "video/x-matroska" => ["mkv"]
}

config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.

config :kakemono, :api_secret, System.get_env("KAKEMONO_API_SECRET") || "dev-secret-change-me"

# Allow setting the backend password through the web UI when none is configured.
# Disabled in prod (see config/prod.exs) so a fresh public deploy cannot be seized.
config :kakemono, :allow_web_password_setup, true

config :kakemono, Oban,
  repo: Kakemono.Repo,
  notifier: Oban.Notifiers.PG,
  engine: Oban.Engines.Lite,
  peer: Oban.Peers.Global,
  queues: [default: 10, media: 2, widgets: 4],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", Kakemono.Widgets.RefreshScheduler,
        args: %{"types" => ["weather", "rss"]}},
       {"0 * * * *", Kakemono.Widgets.RefreshScheduler,
        args: %{"types" => ["air_quality", "instagram"]}},
       {"* * * * *", Kakemono.Scenes.ScheduleWorker}
     ]}
  ]

import_config "#{config_env()}.exs"
