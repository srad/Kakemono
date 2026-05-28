defmodule Kakemono.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    load_secret_from_file()
    bootstrap_backend_password()

    children = [
      # Start TwMerge cache
      TwMerge.Cache,
      KakemonoWeb.Telemetry,
      Kakemono.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:kakemono, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:kakemono, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kakemono.PubSub},
      KakemonoWeb.Presence,
      KakemonoWeb.LoginThrottle,
      # Start the Finch HTTP client for sending emails
      {Finch, name: Kakemono.Finch},
      # Start a worker by calling: Kakemono.Worker.start_link(arg)
      # {Kakemono.Worker, arg},
      # Start to serve requests, typically the last entry
      {Oban, Application.fetch_env!(:kakemono, Oban)},
      KakemonoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kakemono.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp load_secret_from_file do
    if path = Kakemono.DataDir.secret_file() do
      case File.read(path) do
        {:ok, secret} -> Application.put_env(:kakemono, :api_secret, String.trim(secret))
        _ -> :ok
      end
    end
  end

  defp bootstrap_backend_password do
    if Kakemono.BackendAuth.enabled?() and not Kakemono.BackendAuth.configured?() do
      case System.get_env("KAKEMONO_BACKEND_PASSWORD") do
        password when is_binary(password) and password != "" ->
          case Kakemono.BackendAuth.set_password(password) do
            {:error, :too_short} ->
              raise "KAKEMONO_BACKEND_PASSWORD must be at least " <>
                      "#{Kakemono.BackendAuth.min_password_length()} characters"

            _ ->
              :ok
          end

        _ ->
          :ok
      end
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KakemonoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") != nil
  end
end
