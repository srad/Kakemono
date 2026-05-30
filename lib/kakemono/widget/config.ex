defmodule Kakemono.Widget.Config do
  @moduledoc """
  Pure generators that derive a widget's JSON Schema, default config, and draft
  config from its declarative `fields/0` list (plus `cache_fields/0`).

  This is what lets a widget declare its config in exactly one place: the field
  list drives the editor form, the coercion, the defaults, and the validation
  schema. A widget can still override `config_schema/0` (etc.) if a derived
  result ever falls short.

  Recognized field keys:
    * `:key` — config key (string)
    * `:type` — `:text | :number | :checkbox | :select | :playlist_select |
      :calendar_select | :location_search | :timezone_search | :password`
    * `:required` — required in the editor form (drives coercion)
    * `:schema_optional` — when true, a `required: true` field is NOT added to
      the JSON Schema `required` list (e.g. a value the UI always fills in via a
      hook, but that the schema treats as optional)
    * `:default` — value placed in `default_config/0`
    * `:options` — `[{value, label}]` for `:select`, or `[value]` for
      `:timezone_search` (drives the schema `enum`)
    * `:min` / `:max` — numeric bounds (schema `minimum` / `maximum`)
    * `:integer` — `:number` field that must be a whole number
    * `:min_length` — schema `minLength` for string fields
  """

  @doc "Map of `key => default` for every field that declares a `:default`."
  def default_config(fields) do
    for f <- fields, Map.has_key?(f, :default), into: %{}, do: {f.key, f.default}
  end

  @doc """
  Draft config used before the user has filled required fields. Defaults to the
  full `default_config/0`; widgets whose defaults would mask required input
  (e.g. Weather's placeholder location) override `draft_config/0` to `%{}`.
  """
  def draft_config(fields), do: default_config(fields)

  @doc "Derive a JSON Schema map from the field list and cache-field list."
  def config_schema(fields, cache_fields \\ []) do
    field_props = Enum.map(fields, fn f -> {f.key, property(f)} end)
    cache_props = Enum.map(cache_fields, fn {k, t} -> {k, %{"type" => cache_type(t)}} end)
    props = Map.new(field_props ++ cache_props)

    required = for f <- fields, f[:required] && !f[:schema_optional], do: f.key

    base = %{"type" => "object", "properties" => props, "additionalProperties" => false}
    if required == [], do: base, else: Map.put(base, "required", required)
  end

  defp property(%{type: :number} = f) do
    %{"type" => if(f[:integer], do: "integer", else: "number")}
    |> put_if("minimum", f[:min])
    |> put_if("maximum", f[:max])
  end

  defp property(%{type: :checkbox}), do: %{"type" => "boolean"}

  defp property(%{type: :playlist_select}), do: %{"type" => "integer", "minimum" => 1}
  defp property(%{type: :calendar_select}), do: %{"type" => "integer", "minimum" => 1}

  defp property(%{type: :select} = f), do: %{"type" => "string", "enum" => select_enum(f)}

  defp property(%{type: :timezone_search} = f) do
    put_enum(%{"type" => "string"}, Map.get(f, :options))
  end

  # :text, :location_search, :password
  defp property(f), do: put_if(%{"type" => "string"}, "minLength", f[:min_length])

  defp select_enum(%{options: opts}), do: for({val, _label} <- opts, val != "", do: val)
  defp select_enum(_), do: []

  defp put_enum(map, nil), do: map
  defp put_enum(map, opts), do: Map.put(map, "enum", opts)

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp cache_type(t) when is_binary(t), do: t
  defp cache_type(t) when is_atom(t), do: Atom.to_string(t)
end
