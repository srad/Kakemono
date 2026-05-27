defmodule Kakemono.Widgets.RssScheduler do
  @moduledoc """
  Oban.Cron entry: every 15 minutes, enqueues one `RssFetchWorker` job per
  active RSS widget instance.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Widgets.{Instance, RssFetchWorker}

  @impl Oban.Worker
  def perform(_job) do
    ids =
      from(i in Instance, where: i.widget_type == "rss", select: i.id)
      |> Repo.all()

    Enum.each(ids, fn id ->
      %{instance_id: id}
      |> RssFetchWorker.new()
      |> Oban.insert!()
    end)

    {:ok, length(ids)}
  end
end
