defmodule Kakemono.Widgets do
  @moduledoc "Widgets context: CRUD on widget_instances + type registry passthrough."
  import Ecto.Query
  alias Kakemono.Repo
  alias Kakemono.Widgets.{Instance, Registry}

  def list_types,
    do:
      Registry.all()
      |> Enum.map(fn mod ->
        %{type: mod.type(), name: mod.name(), icon: mod.icon(), module: mod}
      end)

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

  defp initial_config(mod, :draft), do: mod.draft_config()
  defp initial_config(mod, :default), do: mod.default_config()

  @doc "Update an instance's config (re-validated against its schema)."
  def update_config(%Instance{widget_type: type} = inst, new_config) do
    case Registry.fetch(type) do
      nil ->
        {:error, :unknown_widget_type}

      mod ->
        old_config = inst.config || %{}
        merged = mod.merge_config(old_config, new_config || %{})

        with :ok <- validate_config(mod, merged),
             {:ok, updated} <- inst |> Instance.changeset(%{config: merged}) |> Repo.update() do
          mod.on_config_change(updated, old_config)
          {:ok, updated}
        end
    end
  end

  @doc "Broadcast a widget config update so displays/editors refresh."
  def broadcast_config_updated(instance_id) do
    Phoenix.PubSub.broadcast(
      Kakemono.PubSub,
      "widgets",
      {:widget_config_updated, %{instance_id: instance_id}}
    )
  end

  def delete_instance(%Instance{} = i), do: Repo.delete(i)

  @doc """
  Dispatch a prefetch call to a widget module if it implements `prefetch/1`.
  Called by the display LiveView on mount and scene-change to lazily populate
  empty caches.
  """
  def prefetch_instance(%Instance{widget_type: type} = inst) do
    case Registry.fetch(type) do
      nil -> :ok
      mod -> mod.prefetch(inst)
    end
  end

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
