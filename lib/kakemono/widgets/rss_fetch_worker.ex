defmodule Kakemono.Widgets.RssFetchWorker do
  @moduledoc """
  Fetches and parses an RSS feed for a single RSS widget instance, caching
  the results in `instance.config["cached_items"]` and `instance.config["feed_title"]`.

  Enqueued by `Kakemono.Widgets.RssScheduler` (Oban.Cron) every 15 minutes.
  HTTP client is `Req`. Tests stub via `Req.Test` — see `config :kakemono, :req_options`.
  """
  use Oban.Worker,
    queue: :widgets,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]]

  alias Kakemono.Widgets
  alias Kakemono.Widgets.{Instance, Rss}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id}}) do
    case Widgets.get_instance(id) do
      %Instance{widget_type: "rss", config: cfg} = inst ->
        url = cfg["url"]

        with {:ok, body} <- fetch(url),
             {feed_title, items} = Rss.parse_feed(body),
             max = cfg["max_items"] || 5,
             trimmed = Enum.take(items, max),
             update = Map.merge(cfg, %{"cached_items" => trimmed, "feed_title" => feed_title}),
             {:ok, _} <- Widgets.update_config(inst, update) do
          broadcast(inst.id)
          :ok
        end

      %Instance{widget_type: type} ->
        {:error, {:wrong_type, type}}

      nil ->
        :ok
    end
  end

  defp fetch(url) do
    opts = Application.get_env(:kakemono, :req_options, [])

    case Req.get(url, opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        # Req auto-decoded JSON — unlikely for RSS but handle gracefully
        {:error, {:unexpected_content_type, body}}

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
