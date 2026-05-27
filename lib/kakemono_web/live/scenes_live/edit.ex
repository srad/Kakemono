defmodule KakemonoWeb.ScenesLive.Edit do
  use KakemonoWeb, :live_view
  alias Kakemono.{Scenes, Widgets, Playlists}
  alias Kakemono.Widgets.Registry

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scene = Scenes.get(String.to_integer(id))

    if is_nil(scene) do
      {:ok, push_navigate(socket, to: ~p"/c/scenes")}
    else
      mount_scene(scene, socket)
    end
  end

  defp mount_scene(scene, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Kakemono.PubSub, "widgets")
    end

    instances = Widgets.list_instances_for(scene.id)
    types = Widgets.list_types()

    {:ok,
     socket
     |> assign(:scene, scene)
     |> assign(:instances, instances)
     |> assign(:types, types)
     |> assign(:playlists, Playlists.list())
     |> assign(:editing_id, nil)}
  end

  # ---------------------------------------------------------------------------
  # Layout events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event(
        "create_and_place",
        %{"type" => type},
        %{assigns: %{scene: %{mode: "fullscreen_widget"} = scene}} = socket
      ) do
    prev_id = scene.layout["widget_instance_id"]

    with {:ok, inst} <- Widgets.create_draft_instance(type, scene.id, %{}),
         {:ok, scene} <-
           Scenes.update(scene, %{layout: %{"widget_instance_id" => inst.id}}) do
      maybe_delete_previous_fullscreen(prev_id, inst.id, scene.id)

      {:noreply,
       socket
       |> assign(:scene, scene)
       |> assign(:instances, Widgets.list_instances_for(scene.id))
       |> assign(:editing_id, editing_id_for_new_instance(inst))}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, format_errors(cs))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create: #{format_error(reason)}")}
    end
  end

  def handle_event("create_and_place", %{"type" => type}, socket) do
    case Widgets.create_draft_instance(type, socket.assigns.scene.id, %{}) do
      {:ok, inst} ->
        cells = socket.assigns.scene.layout["cells"] || []
        cell = auto_place(cells, inst.id)
        new_cells = cells ++ [cell]
        layout = Map.put(socket.assigns.scene.layout, "cells", new_cells)

        case Scenes.update(socket.assigns.scene, %{layout: layout}) do
          {:ok, scene} ->
            hook_cell =
              Map.merge(cell, %{
                "type" => inst.widget_type,
                "widget_instance_id" => inst.id
              })

            {:noreply,
             socket
             |> assign(:scene, scene)
             |> assign(:instances, Widgets.list_instances_for(scene.id))
             |> assign(:editing_id, editing_id_for_new_instance(inst))
             |> push_event("grid_add_widget", %{cell: hook_cell})}

          {:error, cs} ->
            Widgets.delete_instance(inst)
            {:noreply, put_flash(socket, :error, format_errors(cs))}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create: #{format_error(reason)}")}
    end
  end

  @impl true
  def handle_event("cells_changed", %{"cells" => changed}, socket) do
    changed_map =
      Map.new(changed, fn c ->
        {c["widget_instance_id"],
         %{
           "widget_instance_id" => c["widget_instance_id"],
           "x" => c["x"],
           "y" => c["y"],
           "w" => c["w"],
           "h" => c["h"]
         }}
      end)

    existing = socket.assigns.scene.layout["cells"] || []

    updated_cells =
      Enum.map(existing, fn cell ->
        Map.get(changed_map, cell["widget_instance_id"], cell)
      end)

    layout = Map.put(socket.assigns.scene.layout, "cells", updated_cells)

    case Scenes.update(socket.assigns.scene, %{layout: layout}) do
      {:ok, scene} -> {:noreply, assign(socket, :scene, scene)}
      {:error, cs} -> {:noreply, put_flash(socket, :error, format_errors(cs))}
    end
  end

  @impl true
  def handle_event("remove_from_canvas", %{"widget_instance_id" => raw_id}, socket) do
    id = String.to_integer(to_string(raw_id))

    cells =
      (socket.assigns.scene.layout["cells"] || [])
      |> Enum.reject(&(&1["widget_instance_id"] == id))

    layout = Map.put(socket.assigns.scene.layout, "cells", cells)

    case Scenes.update(socket.assigns.scene, %{layout: layout}) do
      {:ok, scene} ->
        {:noreply,
         socket
         |> assign(:scene, scene)
         |> push_event("grid_remove_widget", %{widget_instance_id: id})}

      {:error, cs} ->
        {:noreply, put_flash(socket, :error, format_errors(cs))}
    end
  end

  # ---------------------------------------------------------------------------
  # Config modal events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_config", %{"widget_instance_id" => id}, socket) do
    {:noreply, assign(socket, :editing_id, String.to_integer(to_string(id)))}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  @impl true
  def handle_event("save_config", %{"instance_id" => id_str, "config" => raw_config}, socket) do
    instance = Widgets.get_instance!(String.to_integer(id_str))

    case coerce_config_params(instance.widget_type, raw_config, socket.assigns.playlists) do
      {:ok, coerced} ->
        case Widgets.update_config(instance, coerced) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:instances, Widgets.list_instances_for(socket.assigns.scene.id))
             |> assign(:editing_id, nil)
             |> put_flash(:info, "Config saved")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Save failed: #{format_error(reason)}")}
        end

      {:error, msg} ->
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  # ---------------------------------------------------------------------------
  # Instance management
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("delete_instance", %{"id" => id}, socket) do
    case Widgets.get_instance(String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      inst ->
        {:ok, _} = Widgets.delete_instance(inst)

        cells =
          (socket.assigns.scene.layout["cells"] || [])
          |> Enum.reject(&(&1["widget_instance_id"] == inst.id))

        layout = Map.put(socket.assigns.scene.layout, "cells", cells)
        {:ok, scene} = Scenes.update(socket.assigns.scene, %{layout: layout})

        {:noreply,
         socket
         |> assign(:scene, scene)
         |> assign(:instances, Widgets.list_instances_for(scene.id))
         |> push_event("grid_remove_widget", %{widget_instance_id: inst.id})}
    end
  end

  @impl true
  def handle_event("set_fullscreen_widget", %{"widget_instance_id" => wid}, socket) do
    id = String.to_integer(wid)
    layout = %{"widget_instance_id" => id}

    case Scenes.update(socket.assigns.scene, %{layout: layout}) do
      {:ok, scene} ->
        {:noreply, socket |> assign(:scene, scene) |> put_flash(:info, "Fullscreen widget set")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update scene")}
    end
  end

  # ---------------------------------------------------------------------------
  # Scene metadata
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("rename_scene", %{"name" => name}, socket) do
    case Scenes.update(socket.assigns.scene, %{name: String.trim(name)}) do
      {:ok, scene} -> {:noreply, assign(socket, :scene, scene)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not rename scene")}
    end
  end

  @impl true
  def handle_event("set_aspect_ratio", %{"aspect_ratio" => ratio}, socket) do
    case Scenes.update(socket.assigns.scene, %{aspect_ratio: ratio}) do
      {:ok, scene} -> {:noreply, assign(socket, :scene, scene)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update aspect ratio")}
    end
  end

  @impl true
  def handle_event(
        "set_canvas_settings",
        %{"aspect_ratio" => ratio, "orientation" => orientation, "color_scheme" => color_scheme},
        socket
      ) do
    case Scenes.update(socket.assigns.scene, %{
           aspect_ratio: ratio,
           orientation: orientation,
           color_scheme: color_scheme
         }) do
      {:ok, scene} -> {:noreply, assign(socket, :scene, scene)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update canvas settings")}
    end
  end

  # ---------------------------------------------------------------------------
  # Schedule
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("save_schedule", %{"schedule" => raw}, socket) do
    days = (raw["days"] || []) |> Enum.map(&String.to_integer/1)
    start_hour = String.to_integer(raw["start_hour"])
    end_hour = String.to_integer(raw["end_hour"])
    schedule = %{"days" => days, "start_hour" => start_hour, "end_hour" => end_hour}

    case Scenes.update(socket.assigns.scene, %{schedule: schedule}) do
      {:ok, scene} ->
        {:noreply, socket |> assign(:scene, scene) |> put_flash(:info, "Schedule saved")}

      {:error, cs} ->
        {:noreply, put_flash(socket, :error, format_errors(cs))}
    end
  end

  @impl true
  def handle_event("clear_schedule", _params, socket) do
    case Scenes.update(socket.assigns.scene, %{schedule: nil}) do
      {:ok, scene} ->
        {:noreply, socket |> assign(:scene, scene) |> put_flash(:info, "Schedule cleared")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not clear schedule")}
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:widget_config_updated, %{instance_id: id}}, socket) do
    scene_id = socket.assigns.scene.id

    case Widgets.get_instance(id) do
      %{scene_id: ^scene_id} ->
        {:noreply, assign(socket, :instances, Widgets.list_instances_for(scene_id))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp cells_for_hook(scene, instances) do
    cells = scene.layout["cells"] || []
    inst_map = Map.new(instances, &{&1.id, &1})

    Enum.flat_map(cells, fn cell ->
      case Map.get(inst_map, cell["widget_instance_id"]) do
        nil ->
          []

        inst ->
          [
            %{
              widget_instance_id: inst.id,
              x: cell["x"],
              y: cell["y"],
              w: cell["w"],
              h: cell["h"],
              type: inst.widget_type
            }
          ]
      end
    end)
  end

  defp maybe_delete_previous_fullscreen(prev_id, new_id, scene_id)
       when is_integer(prev_id) and prev_id != 0 and prev_id != new_id do
    case Widgets.get_instance(prev_id) do
      %{scene_id: ^scene_id} = old -> Widgets.delete_instance(old)
      _ -> :ok
    end
  end

  defp maybe_delete_previous_fullscreen(_, _, _), do: :ok

  defp editing_id_for_new_instance(inst) do
    if needs_initial_config?(inst), do: inst.id
  end

  defp needs_initial_config?(inst) do
    inst.widget_type
    |> config_fields_for()
    |> Enum.any?(fn field ->
      field[:required] && blank_config_value?(Map.get(inst.config || %{}, field.key))
    end)
  end

  defp blank_config_value?(nil), do: true
  defp blank_config_value?(""), do: true
  defp blank_config_value?(_), do: false

  defp auto_place(cells, widget_id) do
    occupied =
      cells
      |> Enum.flat_map(fn c ->
        for x <- c["x"]..(c["x"] + c["w"] - 1),
            y <- c["y"]..(c["y"] + c["h"] - 1),
            do: {x, y}
      end)
      |> MapSet.new()

    {x, y} =
      Enum.find(
        for(y <- 0..10, x <- 0..10, do: {x, y}),
        {0, 0},
        fn {x, y} ->
          Enum.all?(for(dx <- 0..1, dy <- 0..1, do: {x + dx, y + dy}), fn pos ->
            not MapSet.member?(occupied, pos)
          end)
        end
      )

    %{"widget_instance_id" => widget_id, "x" => x, "y" => y, "w" => 2, "h" => 2}
  end

  defp coerce_config_params(type, raw_params, _playlists) do
    case Registry.fetch(type) do
      nil ->
        {:error, "Unknown widget type: #{type}"}

      mod ->
        fields = if function_exported?(mod, :config_fields, 0), do: mod.config_fields(), else: []

        {config, errors} =
          Enum.reduce(fields, {%{}, []}, fn field, {acc, errs} ->
            raw = raw_params[field.key]

            case coerce_value(raw, field) do
              {:ok, nil} when field.required ->
                {acc, ["#{field[:label] || field.key} is required" | errs]}

              {:ok, nil} ->
                {acc, errs}

              {:ok, value} ->
                {Map.put(acc, field.key, value), errs}

              {:error, msg} ->
                {acc, [msg | errs]}
            end
          end)

        if errors == [] do
          {:ok, config}
        else
          {:error, Enum.join(Enum.reverse(errors), "; ")}
        end
    end
  end

  defp coerce_value(nil, %{type: :checkbox}), do: {:ok, false}
  defp coerce_value("true", %{type: :checkbox}), do: {:ok, true}
  defp coerce_value("on", %{type: :checkbox}), do: {:ok, true}
  defp coerce_value(_, %{type: :checkbox}), do: {:ok, false}

  defp coerce_value(nil, _field), do: {:ok, nil}
  defp coerce_value("", _field), do: {:ok, nil}

  defp coerce_value(v, %{type: :location_search}) when is_binary(v) do
    case String.trim(v) do
      "" -> {:ok, nil}
      s -> {:ok, s}
    end
  end

  defp coerce_value(v, %{type: :playlist_select}) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> {:ok, i}
      :error -> {:error, "Invalid playlist selection"}
    end
  end

  defp coerce_value(v, %{type: :number, integer: true}) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> {:ok, i}
      :error -> {:error, "must be a whole number"}
    end
  end

  defp coerce_value(v, %{type: :number}) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> {:ok, f}
      :error -> {:error, "must be a number"}
    end
  end

  defp coerce_value(v, _field), do: {:ok, v}

  defp format_error({:invalid_config, errors}) do
    errors
    |> Enum.map_join("; ", fn
      {msg, _} when is_binary(msg) -> msg
      other -> inspect(other)
    end)
  end

  defp format_error(other), do: inspect(other)

  defp format_errors(cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map(fn {k, msgs} -> "#{k}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  defp type_label(types, type) do
    Enum.find_value(types, type, fn t -> if t.type == type, do: t.name end)
  end

  defp config_fields_for(nil), do: []

  defp config_fields_for(type) do
    case Registry.fetch(type) do
      nil -> []
      mod -> if function_exported?(mod, :config_fields, 0), do: mod.config_fields(), else: []
    end
  end

  defp placed_ids(scene) do
    scene.layout["cells"]
    |> List.wrap()
    |> Enum.map(& &1["widget_instance_id"])
    |> MapSet.new()
  end

  # ---------------------------------------------------------------------------
  # Template
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :cells_json,
        Jason.encode!(cells_for_hook(assigns.scene, assigns.instances))
      )

    assigns = assign(assigns, :placed_ids, placed_ids(assigns.scene))

    ~H"""
    <div class="flex h-screen overflow-hidden bg-gray-100">
      <%!-- Sidebar --%>
      <aside class="w-72 flex-none flex flex-col border-r bg-white overflow-y-auto">
        <%!-- Header --%>
        <div class="p-4 border-b space-y-2">
          <div class="flex items-center justify-between">
            <.link navigate={~p"/c/scenes"} class="text-sm text-blue-600 hover:underline">
              ← All scenes
            </.link>
            <a
              href={~p"/d/preview?scene=#{@scene.name}"}
              target="_blank"
              rel="noopener"
              title="Open this scene in the display viewer in a new tab"
              class="inline-flex items-center gap-1 text-xs px-2 py-1 rounded border border-gray-300
                     text-gray-600 hover:text-gray-900 hover:border-gray-400 hover:bg-gray-50"
            >
              <span aria-hidden="true">↗</span> Preview
            </a>
          </div>
          <form phx-submit="rename_scene" class="flex items-center gap-1">
            <input
              type="text"
              name="name"
              value={@scene.name}
              class="flex-1 font-bold text-lg border-0 border-b border-transparent
                     hover:border-gray-300 focus:border-blue-500 focus:ring-0
                     bg-transparent px-0 py-0.5"
            />
            <button type="submit" class="text-xs text-gray-400 hover:text-gray-700 shrink-0">
              ✓
            </button>
          </form>
          <p class="text-xs text-gray-400">mode: {@scene.mode}</p>
        </div>

        <%!-- Canvas settings — dashboard mode only --%>
        <section :if={@scene.mode == "dashboard"} class="p-4 border-b">
          <h2 class="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">
            Canvas
          </h2>
          <form phx-submit="set_canvas_settings" class="space-y-2">
            <label class="block">
              <span class="block text-xs text-gray-500 mb-1">Ratio</span>
              <select name="aspect_ratio" class="w-full border rounded px-2 py-1 text-sm">
                <option
                  :for={r <- Kakemono.Scenes.Scene.aspect_ratios()}
                  value={r}
                  selected={r == @scene.aspect_ratio}
                >
                  {r}
                </option>
              </select>
            </label>
            <label class="block">
              <span class="block text-xs text-gray-500 mb-1">Orientation</span>
              <select name="orientation" class="w-full border rounded px-2 py-1 text-sm">
                <option
                  :for={o <- Kakemono.Scenes.Scene.orientations()}
                  value={o}
                  selected={o == @scene.orientation}
                >
                  {o}
                </option>
              </select>
            </label>
            <label class="block">
              <span class="block text-xs text-gray-500 mb-1">Theme</span>
              <select name="color_scheme" class="w-full border rounded px-2 py-1 text-sm">
                <option
                  :for={s <- Kakemono.Scenes.Scene.color_schemes()}
                  value={s}
                  selected={s == @scene.color_scheme}
                >
                  {s}
                </option>
              </select>
            </label>
            <button
              type="submit"
              class="px-2 py-1 text-xs border rounded hover:bg-gray-50 text-gray-600"
            >
              Apply
            </button>
          </form>
        </section>

        <%!-- Add widget buttons — available in both modes --%>
        <section
          :if={@scene.mode in ["dashboard", "fullscreen_widget"]}
          class="p-4 border-b"
        >
          <h2 class="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">
            Add Widget
          </h2>
          <div class="grid grid-cols-2 gap-2">
            <button
              :for={t <- @types}
              phx-click="create_and_place"
              phx-value-type={t.type}
              class="flex items-center gap-2 px-3 py-2 text-sm border rounded hover:bg-gray-50
                     text-gray-700 font-medium"
            >
              <span>{widget_icon(t.type)}</span>
              <span class="truncate">{t.name}</span>
            </button>
          </div>
        </section>

        <%!-- Fullscreen widget picker --%>
        <section :if={@scene.mode == "fullscreen_widget"} class="p-4 border-b space-y-2">
          <h2 class="text-xs font-semibold uppercase tracking-wide text-gray-400">
            Fullscreen Widget
          </h2>
          <form phx-submit="set_fullscreen_widget" class="flex gap-2 items-end">
            <div class="flex-1">
              <select
                name="widget_instance_id"
                class="border rounded px-2 py-1 w-full text-sm"
                required
              >
                <option value="">— choose instance —</option>
                <option
                  :for={i <- @instances}
                  value={i.id}
                  selected={@scene.layout["widget_instance_id"] == i.id}
                >
                  #{i.id} {type_label(@types, i.widget_type)}
                </option>
              </select>
            </div>
            <button
              type="submit"
              class="bg-primary text-primary-foreground px-3 py-1.5 rounded text-sm"
            >
              Set
            </button>
          </form>
          <p :if={@instances == []} class="text-xs text-gray-400">
            Click an "Add Widget" button above to create the fullscreen widget.
          </p>
        </section>

        <%!-- Placed instances list --%>
        <section :if={@scene.mode == "dashboard"} class="p-4 border-b flex-1">
          <h2 class="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">
            Placed Widgets
          </h2>
          <p :if={MapSet.size(@placed_ids) == 0} class="text-xs text-gray-400">
            None — click Add Widget above.
          </p>
          <ul class="space-y-1">
            <li
              :for={cell <- @scene.layout["cells"] || []}
              class="flex items-center gap-1 text-sm py-1"
            >
              <span class="flex-1 truncate text-gray-700">
                {widget_icon(inst_type(@instances, cell["widget_instance_id"]))}
                {type_label(@types, inst_type(@instances, cell["widget_instance_id"]))}
                <span class="text-gray-400 text-xs">#{cell["widget_instance_id"]}</span>
              </span>
              <button
                phx-click="open_config"
                phx-value-widget_instance_id={cell["widget_instance_id"]}
                class="text-xs text-blue-600 hover:underline px-1"
              >
                Config
              </button>
              <button
                phx-click="remove_from_canvas"
                phx-value-widget_instance_id={cell["widget_instance_id"]}
                class="text-xs text-red-500 hover:underline px-1"
              >
                ✕
              </button>
            </li>
          </ul>
        </section>

        <%!-- All instances (with delete) --%>
        <section :if={@instances != []} class="p-4 border-b">
          <h2 class="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">
            All Instances
          </h2>
          <ul class="space-y-1">
            <li :for={i <- @instances} class="flex items-center gap-1 text-xs text-gray-500">
              <span class="flex-1 truncate">#{i.id} {type_label(@types, i.widget_type)}</span>
              <button
                phx-click="open_config"
                phx-value-widget_instance_id={i.id}
                class="hover:text-blue-600 px-1"
                title="Configure"
              >
                ⚙
              </button>
              <button
                phx-click="delete_instance"
                phx-value-id={i.id}
                data-confirm="Delete this widget instance permanently?"
                class="hover:text-red-600 px-1"
                title="Delete"
              >
                🗑
              </button>
            </li>
          </ul>
        </section>

        <%!-- Schedule --%>
        <section class="p-4">
          <h2 class="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">
            Schedule
          </h2>
          <form phx-submit="save_schedule" class="space-y-3">
            <div>
              <div class="flex flex-wrap gap-2 text-xs">
                <label
                  :for={
                    {label, n} <- [
                      {"Mo", 1},
                      {"Tu", 2},
                      {"We", 3},
                      {"Th", 4},
                      {"Fr", 5},
                      {"Sa", 6},
                      {"Su", 7}
                    ]
                  }
                  class="flex items-center gap-1"
                >
                  <input
                    type="checkbox"
                    name="schedule[days][]"
                    value={n}
                    checked={n in ((@scene.schedule || %{})["days"] || [])}
                  />
                  {label}
                </label>
              </div>
            </div>
            <div class="flex gap-2 text-xs">
              <div>
                <label class="block text-gray-400">Start (UTC)</label>
                <input
                  type="number"
                  name="schedule[start_hour]"
                  min="0"
                  max="23"
                  value={(@scene.schedule || %{})["start_hour"]}
                  class="border rounded px-2 py-1 w-16 text-sm"
                  required
                />
              </div>
              <div>
                <label class="block text-gray-400">End (UTC)</label>
                <input
                  type="number"
                  name="schedule[end_hour]"
                  min="0"
                  max="23"
                  value={(@scene.schedule || %{})["end_hour"]}
                  class="border rounded px-2 py-1 w-16 text-sm"
                  required
                />
              </div>
            </div>
            <div class="flex gap-2">
              <button
                type="submit"
                class="bg-primary text-primary-foreground px-3 py-1 rounded text-xs"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="clear_schedule"
                class="border px-3 py-1 rounded text-xs text-red-600"
              >
                Clear
              </button>
            </div>
          </form>
        </section>
      </aside>

      <%!-- Main canvas --%>
      <main class="flex-1 overflow-hidden bg-gray-100 p-4">
        <%!-- Dashboard grid --%>
        <div :if={@scene.mode == "dashboard"} class="flex h-full min-h-0 flex-col">
          <div class="dashboard-editor-frame flex min-h-0 flex-1 items-center justify-center overflow-auto rounded-xl bg-neutral-950 p-4">
            <div
              id="grid-canvas"
              phx-hook="GridEditor"
              phx-update="ignore"
              data-cells={@cells_json}
              data-aspect-ratio={@scene.aspect_ratio}
              data-orientation={@scene.orientation}
              data-color-scheme={@scene.color_scheme}
              class="grid-stack dashboard-editor-surface"
            >
            </div>
          </div>
        </div>

        <%!-- Fullscreen widget info --%>
        <div :if={@scene.mode == "fullscreen_widget"} class="flex items-center justify-center h-full">
          <div class="text-center space-y-2">
            <p class="text-2xl">
              {widget_icon(inst_type(@instances, @scene.layout["widget_instance_id"]))}
            </p>
            <p class="text-gray-600">
              {type_label(@types, inst_type(@instances, @scene.layout["widget_instance_id"]))}
              <span class="text-gray-400 text-sm">fills entire display</span>
            </p>
            <p
              :if={
                @scene.layout["widget_instance_id"] == 0 or
                  is_nil(@scene.layout["widget_instance_id"])
              }
              class="text-sm text-gray-400"
            >
              Select a widget instance in the sidebar.
            </p>
          </div>
        </div>
      </main>

      <%!-- Config modal --%>
      <div
        :if={@editing_id != nil}
        class="fixed inset-0 z-50 flex items-center justify-center"
      >
        <div
          class="absolute inset-0 bg-black/40"
          phx-click="cancel_edit"
        />
        <div class="relative bg-white rounded-xl shadow-2xl w-full max-w-md mx-4 z-10">
          <div class="flex items-center justify-between px-5 py-4 border-b">
            <h2 class="font-semibold">
              Configure {type_label(@types, inst_type(@instances, @editing_id))}
              <span class="text-gray-400 font-normal text-sm">#{@editing_id}</span>
            </h2>
            <button
              phx-click="cancel_edit"
              class="text-gray-400 hover:text-gray-600 text-xl leading-none"
            >
              ×
            </button>
          </div>

          <form phx-submit="save_config" class="p-5 space-y-4">
            <input type="hidden" name="instance_id" value={@editing_id} />
            <p
              :if={config_fields_for(inst_type(@instances, @editing_id)) == []}
              class="text-sm text-gray-500"
            >
              This widget has no configurable options.
            </p>
            <%= for field <- config_fields_for(inst_type(@instances, @editing_id)) do %>
              <%= if field[:hidden] do %>
                {render_config_field(assigns, field)}
              <% else %>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    {field.label}{if field.required, do: " *", else: ""}
                  </label>
                  {render_config_field(assigns, field)}
                </div>
              <% end %>
            <% end %>
            <div class="flex gap-2 pt-2">
              <button
                type="submit"
                class="bg-primary text-primary-foreground px-4 py-2 rounded text-sm"
              >
                Save
              </button>
              <button type="button" phx-click="cancel_edit" class="border px-4 py-2 rounded text-sm">
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp render_config_field(assigns, %{hidden: true} = field) do
    instance = Enum.find(assigns.instances, &(&1.id == assigns.editing_id))
    current = if instance, do: Map.get(instance.config, field.key), else: nil
    assigns = assign(assigns, field: field, current: current)

    ~H"""
    <input type="hidden" name={"config[#{@field.key}]"} value={@current} />
    """
  end

  defp render_config_field(assigns, field) do
    instance = Enum.find(assigns.instances, &(&1.id == assigns.editing_id))
    current = if instance, do: Map.get(instance.config, field.key), else: nil

    case field.type do
      :location_search ->
        assigns = assign(assigns, field: field, current: current)

        ~H"""
        <div
          class="kw-loc-wrap relative"
          id={"loc-#{@field.key}"}
          phx-hook="LocationSearch"
          phx-update="ignore"
        >
          <input
            type="text"
            name={"config[#{@field.key}]"}
            value={@current || ""}
            placeholder={Map.get(@field, :placeholder, "")}
            autocomplete="off"
            class="kw-loc-input border rounded px-2 py-1 w-full text-sm"
          />
          <ul class="kw-loc-results"></ul>
        </div>
        """

      :playlist_select ->
        assigns = assign(assigns, field: field, current: current)

        ~H"""
        <select name={"config[#{@field.key}]"} class="border rounded px-2 py-1 w-full text-sm">
          <option value="">— choose playlist —</option>
          <option :for={pl <- @playlists} value={pl.id} selected={@current == pl.id}>{pl.name}</option>
        </select>
        """

      :select ->
        assigns = assign(assigns, field: field, current: current)

        ~H"""
        <select name={"config[#{@field.key}]"} class="border rounded px-2 py-1 w-full text-sm">
          <option :for={{val, lbl} <- @field.options} value={val} selected={@current == val}>
            {lbl}
          </option>
        </select>
        """

      :checkbox ->
        assigns = assign(assigns, field: field, current: current)

        ~H"""
        <input type="checkbox" name={"config[#{@field.key}]"} value="true" checked={@current == true} />
        """

      :number ->
        assigns = assign(assigns, field: field, current: current)

        ~H"""
        <input
          type="number"
          name={"config[#{@field.key}]"}
          min={@field[:min]}
          max={@field[:max]}
          step={Map.get(@field, :step, "any")}
          value={@current}
          placeholder={Map.get(@field, :placeholder, "")}
          class="border rounded px-2 py-1 w-full text-sm"
        />
        """

      _ ->
        assigns = assign(assigns, field: field, current: current)

        ~H"""
        <input
          type="text"
          name={"config[#{@field.key}]"}
          value={@current || ""}
          placeholder={Map.get(@field, :placeholder, "")}
          class="border rounded px-2 py-1 w-full text-sm"
        />
        """
    end
  end

  defp inst_type(instances, id) do
    case Enum.find(instances, &(&1.id == id)) do
      nil -> nil
      inst -> inst.widget_type
    end
  end

  defp widget_icon("clock"), do: "🕐"
  defp widget_icon("weather"), do: "🌤"
  defp widget_icon("slideshow"), do: "🖼"
  defp widget_icon("rss"), do: "📰"
  defp widget_icon(_), do: "▪"
end
