defmodule Kakemono.Widget do
  @moduledoc """
  Behaviour every widget module must implement, plus a `use Kakemono.Widget`
  macro that supplies sensible defaults so a widget only declares what it needs.

  A widget is a compile-time module discovered by `Kakemono.Widgets.Registry`
  (any module that `use Kakemono.Widget`). Instances are persisted as rows in
  `widget_instances` keyed by `widget_type` (the string from `type/0`). Each
  instance has a `config` map validated against `config_schema/0`, which by
  default is **derived** from the declarative `fields/0` list (see
  `Kakemono.Widget.Config`) — so config is declared in one place.

  ## Minimal widget

      defmodule Kakemono.Widgets.Foo do
        use Kakemono.Widget

        @impl true
        def type, do: "foo"
        @impl true
        def name, do: "Foo"
        @impl true
        def render(assigns), do: ~H"..."
      end

  Data-fetching widgets additionally implement `fetch/1` (and usually
  `cache_fields/0`, `prefetch/1`, `on_config_change/2`); the generic
  `Kakemono.Widgets.FetchWorker` and `RefreshScheduler` handle scheduling.
  """

  alias Kakemono.Widgets.Instance

  @doc "Stable string used as the discriminator in the widget_instances table."
  @callback type() :: String.t()

  @doc "Human-readable label for the picker UI."
  @callback name() :: String.t()

  @doc "Emoji/text glyph shown in the editor widget picker."
  @callback icon() :: String.t()

  @doc "Declarative config field list — the single source of config truth."
  @callback fields() :: [map()]

  @doc "Keys (with JSON types) the fetch worker writes; whitelisted in the schema."
  @callback cache_fields() :: [{String.t(), String.t() | atom()}]

  @doc "JSON Schema (plain map). Derived from fields/0 + cache_fields/0 by default."
  @callback config_schema() :: map()

  @doc "Default config for a new instance. Derived from fields/0 by default."
  @callback default_config() :: map()

  @doc "Config template used by the editor before required fields are filled."
  @callback draft_config() :: map()

  @doc "Render the widget. Assigns include at least `%{instance: %Instance{}}`."
  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc "UI field descriptors for the editor — same shape as fields/0."
  @callback config_fields() :: [map()]

  @doc """
  Merge a config update onto the existing config. Defaults to `Map.merge/2`;
  override to invalidate derived cache keys when source keys change.
  """
  @callback merge_config(old :: map(), new :: map()) :: map()

  @doc """
  Called after a config update is persisted. Use it to enqueue an immediate
  refetch when a source key changed. Defaults to no-op.
  """
  @callback on_config_change(Instance.t(), old_config :: map()) :: :ok

  @doc """
  Called when a display first mounts a scene with this widget. Should enqueue a
  fetch only if the cache is empty. Idempotent. Defaults to no-op.
  """
  @callback prefetch(Instance.t()) :: :ok

  @doc """
  Fetch remote data for one instance. Return `{:ok, patch}` to have the worker
  persist the patch and broadcast; `:ok` if the widget already persisted its own
  update; `:skip` to do nothing; `{:error, reason}` to trigger an Oban retry.
  """
  @callback fetch(Instance.t()) :: {:ok, map()} | :ok | :skip | {:error, term()}

  @optional_callbacks fetch: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour Kakemono.Widget
      use Phoenix.Component

      @doc false
      def __widget__, do: true

      @impl true
      def icon, do: "▪"

      @impl true
      def fields, do: []

      @impl true
      def cache_fields, do: []

      @impl true
      def config_schema, do: Kakemono.Widget.Config.config_schema(fields(), cache_fields())

      @impl true
      def default_config, do: Kakemono.Widget.Config.default_config(fields())

      @impl true
      def draft_config, do: Kakemono.Widget.Config.draft_config(fields())

      # Backwards-friendly alias: the editor used to call config_fields/0.
      @impl true
      def config_fields, do: fields()

      @impl true
      def merge_config(old, new), do: Map.merge(old, new)

      @impl true
      def on_config_change(_instance, _old_config), do: :ok

      @impl true
      def prefetch(_instance), do: :ok

      defoverridable icon: 0,
                     fields: 0,
                     cache_fields: 0,
                     config_schema: 0,
                     default_config: 0,
                     draft_config: 0,
                     config_fields: 0,
                     merge_config: 2,
                     on_config_change: 2,
                     prefetch: 1
    end
  end
end
