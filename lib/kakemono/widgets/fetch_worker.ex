defmodule Kakemono.Widgets.FetchWorker do
  @moduledoc """
  Generic Oban worker that refreshes one widget instance by delegating to its
  module's `fetch/1`. Replaces the per-widget fetch workers.

  `fetch/1` may return:
    * `{:ok, patch}` — this worker persists the patch via
      `Widgets.update_config/2` and broadcasts the update.
    * `:ok` — the widget already persisted/broadcast its own update.
    * `:skip` — nothing to do (e.g. a backoff window hasn't elapsed).
    * `{:error, reason}` — propagated so Oban retries.

  HTTP clients live in the widget modules; tests stub via `Req.Test`
  (`config :kakemono, :req_options`).
  """
  # `states` excludes terminal states (notably :completed) so a deliberate
  # refetch (e.g. a widget's source/config changed) or a scheduled refresh is
  # not coalesced with a just-completed job. Concurrent/pending fetches are
  # still de-duplicated (e.g. several displays mounting the same scene at once).
  use Oban.Worker,
    queue: :widgets,
    max_attempts: 3,
    unique: [
      period: 60,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Instance, Registry}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id}}) do
    with %Instance{widget_type: type} = inst <- Widgets.get_instance(id),
         mod when not is_nil(mod) <- Registry.fetch(type),
         true <- function_exported?(mod, :fetch, 1) do
      dispatch(mod, inst)
    else
      _ -> :ok
    end
  end

  defp dispatch(mod, inst) do
    case mod.fetch(inst) do
      {:ok, patch} when is_map(patch) ->
        with {:ok, _} <- Widgets.update_config(inst, patch), do: :ok

      :ok ->
        :ok

      :skip ->
        :ok

      {:error, _reason} = error ->
        error
    end
  end
end
