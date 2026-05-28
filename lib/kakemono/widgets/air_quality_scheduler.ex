defmodule Kakemono.Widgets.AirQualityScheduler do
  @moduledoc """
  Oban.Cron entry: every 15 minutes, enqueues one `AirQualityFetchWorker` job per
  active air quality widget instance. Single cron entry per node — no per-instance
  scheduling needed.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Widgets.{Instance, AirQualityFetchWorker}

  @impl Oban.Worker
  def perform(_job) do
    ids =
      from(i in Instance, where: i.widget_type == "air_quality", select: i.id)
      |> Repo.all()

    Enum.each(ids, fn id ->
      %{instance_id: id}
      |> AirQualityFetchWorker.new()
      |> Oban.insert!()
    end)

    {:ok, length(ids)}
  end
end
