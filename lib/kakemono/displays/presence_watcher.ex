defmodule Kakemono.Displays.PresenceWatcher do
  @moduledoc """
  Runs every minute. For each display whose `last_heartbeat_at` is older
  than the offline threshold, broadcasts an `{:display_updated, d}` event
  so the dashboard re-renders its online indicator.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Kakemono.Displays

  @impl true
  def perform(_job) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -Displays.offline_after_seconds(), :second)

    Displays.list()
    |> Enum.each(fn d ->
      if d.last_heartbeat_at && DateTime.compare(d.last_heartbeat_at, cutoff) == :lt do
        Phoenix.PubSub.broadcast(Kakemono.PubSub, "displays", {:display_updated, d})
      end
    end)

    :ok
  end
end
