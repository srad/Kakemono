defmodule Kakemono.Widgets.RefreshScheduler do
  @moduledoc """
  Generic Oban.Cron entry: enqueues one `FetchWorker` job per instance whose
  `widget_type` is listed in the job's `"types"` arg. Replaces the per-widget
  scheduler modules — the crontab declares which widget types refresh at which
  cadence.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Widgets.{FetchWorker, Instance}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"types" => types}}) when is_list(types) do
    ids =
      from(i in Instance, where: i.widget_type in ^types, select: i.id)
      |> Repo.all()

    Enum.each(ids, fn id ->
      %{instance_id: id}
      |> FetchWorker.new()
      |> Oban.insert!()
    end)

    {:ok, length(ids)}
  end
end
