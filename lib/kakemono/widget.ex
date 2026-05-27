defmodule Kakemono.Widget do
  @moduledoc """
  Behaviour every widget module must implement.

  A widget is a compile-time module registered in `Kakemono.Widgets.Registry`.
  Instances are persisted as rows in `widget_instances` keyed by `widget_type`
  (the string returned by `type/0`). Each instance has a `config` map validated
  against `config_schema/0` (JSON Schema, validated via `ex_json_schema`).
  """

  @doc "Stable string used as the discriminator in the widget_instances table."
  @callback type() :: String.t()

  @doc "Human-readable label for the picker UI."
  @callback name() :: String.t()

  @doc "JSON Schema (as a plain map) describing the shape of `config`."
  @callback config_schema() :: map()

  @doc "Default config used when a new instance is created."
  @callback default_config() :: map()

  @doc """
  Optional config template used by the scene editor before the user fills
  required fields. Defaults to `default_config/0` when not implemented.
  """
  @callback draft_config() :: map()

  @doc """
  Render the widget. Assigns are at least `%{instance: %WidgetInstance{}}`.
  Returns a Phoenix.LiveView.Rendered.t() (HEEx) suitable for placement inside
  a grid cell.
  """
  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  UI field descriptors for the config editor. Each map has atom keys:
    - :key (string) — config key
    - :label (string) — display label
    - :type — :text | :number | :checkbox | :select | :playlist_select
    - :required (boolean)
    - :placeholder (string, optional)
    - :min, :max, :step — for :number fields
    - :options — [{value, label}] for :select fields
    - :integer (boolean) — for :number fields that must round-trip as integers
  """
  @callback config_fields() :: [map()]

  @doc """
  Called when a display first mounts a scene containing this widget. The
  implementation should enqueue its fetch worker if (and only if) the cache
  is missing. Idempotent — safe to call on every mount; Oban unique-job
  de-duplication prevents duplicate fetches.

  Widgets that need no remote data (Clock, Slideshow) skip this callback.
  """
  @callback prefetch(Kakemono.Widgets.Instance.t()) :: :ok

  @optional_callbacks config_fields: 0, draft_config: 0, prefetch: 1
end
