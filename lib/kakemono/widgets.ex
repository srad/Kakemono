defmodule Kakemono.Widgets do
  @moduledoc "Widgets context: CRUD on widget_instances + type registry passthrough."
  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Widgets.{Instance, Registry}

  def list_types,
    do:
      Registry.all() |> Enum.map(fn mod -> %{type: mod.type(), name: mod.name(), module: mod} end)

  def list_instances, do: Repo.all(from i in Instance, order_by: [asc: i.id])

  @doc "List instances belonging to a single scene (used by the scene editor)."
  def list_instances_for(scene_id),
    do: Repo.all(from i in Instance, where: i.scene_id == ^scene_id, order_by: [asc: i.id])

  def get_instance(id), do: Repo.get(Instance, id)

  def get_instance!(id), do: Repo.get!(Instance, id)

  @doc """
  Create a widget instance of the given type, owned by `scene_id`. `config` is
  merged on top of the module's default_config and validated against its JSON
  Schema.
  """
  def create_instance(type, scene_id, config \\ %{})
      when is_binary(type) and is_integer(scene_id) do
    do_create_instance(type, scene_id, config, :default, validate?: true)
  end

  @doc """
  Create a widget instance without requiring a complete config yet.

  The scene editor uses this for widgets that need user input before their
  JSON Schema can pass, such as Feed URLs and slideshow playlists. Normal
  callers should use `create_instance/3`.
  """
  def create_draft_instance(type, scene_id, config \\ %{})
      when is_binary(type) and is_integer(scene_id) do
    do_create_instance(type, scene_id, config, :draft, validate?: false)
  end

  defp do_create_instance(type, scene_id, config, config_source, opts) do
    case Registry.fetch(type) do
      nil ->
        {:error, :unknown_widget_type}

      mod ->
        merged = Map.merge(initial_config(mod, config_source), config || %{})

        with :ok <- maybe_validate_config(mod, merged, opts) do
          %Instance{}
          |> Instance.changeset(%{widget_type: type, config: merged, scene_id: scene_id})
          |> Repo.insert()
        end
    end
  end

  defp initial_config(mod, :draft) do
    if function_exported?(mod, :draft_config, 0),
      do: mod.draft_config(),
      else: mod.default_config()
  end

  defp initial_config(mod, :default), do: mod.default_config()

  @doc "Update an instance's config (re-validated against its schema)."
  def update_config(%Instance{widget_type: type} = inst, new_config) do
    case Registry.fetch(type) do
      nil ->
        {:error, :unknown_widget_type}

      mod ->
        old_config = inst.config || %{}
        merged = merge_config_update(type, old_config, new_config || %{})

        with :ok <- validate_config(mod, merged),
             {:ok, updated} <- inst |> Instance.changeset(%{config: merged}) |> Repo.update() do
          post_update(updated, old_config)
          {:ok, updated}
        end
    end
  end

  def delete_instance(%Instance{} = i), do: Repo.delete(i)

  @doc """
  Dispatch a prefetch call to a widget module if it implements `prefetch/1`.
  Called by the display LiveView on mount and scene-change to lazily populate
  empty caches.
  """
  def prefetch_instance(%Instance{widget_type: type} = inst) do
    case Registry.fetch(type) do
      nil ->
        :ok

      mod ->
        if function_exported?(mod, :prefetch, 1) do
          mod.prefetch(inst)
        else
          :ok
        end
    end
  end

  # Only enqueue an immediate fetch when the URL actually changes (user edit),
  # not when the worker writes cached_items back — otherwise we loop forever.
  defp post_update(%Instance{widget_type: "rss", id: id, config: %{"url" => url}}, old_config)
       when is_binary(url) and url != "" do
    if old_config["url"] != url do
      %{instance_id: id}
      |> Kakemono.Widgets.RssFetchWorker.new()
      |> Oban.insert!()
    end

    :ok
  end

  # Refetch weather immediately when the user picks a new location.
  # Skip when only the cached payload changed (worker writeback).
  defp post_update(
         %Instance{
           widget_type: "weather",
           id: id,
           config: %{"latitude" => lat, "longitude" => lon}
         },
         old_config
       )
       when is_number(lat) and is_number(lon) do
    if old_config["latitude"] != lat or old_config["longitude"] != lon do
      %{instance_id: id}
      |> Kakemono.Widgets.WeatherFetchWorker.new()
      |> Oban.insert!()
    end

    :ok
  end

  # Refetch Instagram when the account source changes. Worker writebacks keep
  # the same source keys, so this doesn't loop on cached_items updates.
  defp post_update(%Instance{widget_type: "instagram", id: id, config: cfg}, old_config) do
    if instagram_source_changed?(cfg, old_config) and configured_instagram?(cfg) do
      %{instance_id: id}
      |> Kakemono.Widgets.InstagramFetchWorker.new()
      |> Oban.insert!()
    end

    :ok
  end

  defp post_update(_, _), do: :ok

  defp merge_config_update("instagram", old_config, new_config) do
    merged = Map.merge(old_config, new_config)

    if instagram_source_changed?(merged, old_config) do
      merged
      |> Map.delete("cached_items")
      |> Map.delete("last_error")
      |> Map.delete("last_error_at")
      |> Map.delete("last_fetch_at")
      |> Map.delete("next_fetch_at")
    else
      merged
    end
  end

  defp merge_config_update(_type, old_config, new_config), do: Map.merge(old_config, new_config)

  defp instagram_source_changed?(cfg, old_config) do
    cfg["username"] != old_config["username"] or cfg["access_token"] != old_config["access_token"]
  end

  defp configured_instagram?(%{"username" => username}) when is_binary(username) do
    String.trim(username) != ""
  end

  defp configured_instagram?(_), do: false

  defp validate_config(mod, config) do
    schema = ExJsonSchema.Schema.resolve(mod.config_schema())

    case ExJsonSchema.Validator.validate(schema, config) do
      :ok -> :ok
      {:error, errors} -> {:error, {:invalid_config, errors}}
    end
  end

  defp maybe_validate_config(mod, config, validate?: true), do: validate_config(mod, config)
  defp maybe_validate_config(_mod, _config, validate?: false), do: :ok
end
