defmodule Kakemono.Widgets.InstagramScheduler do
  @moduledoc """
  Oban.Cron entry: once an hour (top of the hour), enqueues one
  `InstagramFetchWorker` job per Instagram widget instance.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Widgets.{Instance, InstagramFetchWorker}

  @impl Oban.Worker
  def perform(_job) do
    ids =
      from(i in Instance, where: i.widget_type == "instagram", select: i.id)
      |> Repo.all()

    Enum.each(ids, fn id ->
      %{instance_id: id}
      |> InstagramFetchWorker.new()
      |> Oban.insert!()
    end)

    {:ok, length(ids)}
  end
end
