defmodule Kakemono.Widgets.AirQualityFetchWorker do
  @moduledoc """
  Fetches current air quality from Open-Meteo (no API key) for a single
  air quality widget instance and writes the response into `instance.config["cached"]`.

  Enqueued by `Kakemono.Widgets.AirQualityScheduler` (Oban.Cron) every 15 minutes,
  once per instance of type `"air_quality"`.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]]

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Instance, AirQuality}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id}}) do
    case Widgets.get_instance(id) do
      %Instance{widget_type: "air_quality", config: cfg} = inst ->
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
    url = AirQuality.open_meteo_url(lat, lon)
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
