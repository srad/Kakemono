defmodule Kakemono.Widgets.WeatherScheduler do
  @moduledoc """
  Oban.Cron entry: every 15 minutes, enqueues one `WeatherFetchWorker` job per
  active weather widget instance. Single cron entry per node — no per-instance
  scheduling needed.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Widgets.{Instance, WeatherFetchWorker}

  @impl Oban.Worker
  def perform(_job) do
    ids =
      from(i in Instance, where: i.widget_type == "weather", select: i.id)
      |> Repo.all()

    Enum.each(ids, fn id ->
      %{instance_id: id}
      |> WeatherFetchWorker.new()
      |> Oban.insert!()
    end)

    {:ok, length(ids)}
  end
end
