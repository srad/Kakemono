import Config

test_partition = System.get_env("MIX_TEST_PARTITION")
test_suffix = if test_partition in [nil, ""], do: "", else: "_#{test_partition}"

data_dir =
  (System.get_env("KAKEMONO_DATA_DIR") ||
     Path.expand("../data/test#{test_suffix}", __DIR__))
  |> Path.expand()

database_path =
  System.get_env("DATABASE_PATH") || Path.join(data_dir, "kakemono_test#{test_suffix}.db")

File.mkdir_p!(Path.dirname(database_path))

config :kakemono,
  data_dir: data_dir,
  uploads_dir: System.get_env("KAKEMONO_UPLOADS_DIR") || Path.join(data_dir, "uploads"),
  backups_dir: System.get_env("KAKEMONO_BACKUPS_DIR") || Path.join(data_dir, "backups"),
  api_secret_file: nil,
  backend_password_file: nil

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kakemono, Kakemono.Repo,
  database: database_path,
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kakemono, KakemonoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "sqWO8bGS9RBA8fAmz1vGOXey/5okZkbbcJntxqX7k1MgRTVl+UeEw9RD23LWsm6R",
  server: false

# In test we don't send emails
config :kakemono, Kakemono.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :kakemono, Oban, testing: :manual

config :kakemono, :api_secret, "test-secret"

# Backend password protection is disabled in tests; covered by dedicated tests
# that re-enable it explicitly.
config :kakemono, :backend_auth, false
