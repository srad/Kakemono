defmodule Kakemono.Widgets.WeatherFetchWorker do
  @moduledoc """
  Fetches current weather from Open-Meteo (no API key) for a single weather
  widget instance and writes the response into `instance.config["cached"]`.

  Enqueued by `Kakemono.Widgets.WeatherScheduler` (Oban.Cron) every 15 minutes,
  once per instance of type `"weather"`.

  HTTP client is `Req`. Tests stub via `Req.Test` — see
  `config :kakemono, :req_options` (we pull stub plug from app env).
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]]

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Instance, Weather}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id}}) do
    case Widgets.get_instance(id) do
      %Instance{widget_type: "weather", config: cfg} = inst ->
        lat = cfg["latitude"]
        lon = cfg["longitude"]

        with {:ok, body} <- fetch(lat, lon),
             {:ok, _} <- Widgets.update_config(inst, %{"cached" => body}) do
          broadcast(inst.id)
          :ok
        end

      %Instance{widget_type: type} ->
        {:error, {:wrong_type, type}}

      nil ->
        :ok
    end
  end

  defp fetch(lat, lon) do
    url = Weather.open_meteo_url(lat, lon)
    opts = Application.get_env(:kakemono, :req_options, [])

    case Req.get(url, opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast(instance_id) do
    Phoenix.PubSub.broadcast(
      Kakemono.PubSub,
      "widgets",
      {:widget_config_updated, %{instance_id: instance_id}}
    )
  end
end
