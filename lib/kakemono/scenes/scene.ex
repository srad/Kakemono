defmodule Kakemono.Scenes.Scene do
  use Ecto.Schema
  import Ecto.Changeset

  @modes ~w(dashboard fullscreen_widget)
  @aspect_ratios ~w(16:9 16:10 4:3 1:1)
  @orientations ~w(landscape portrait)
  @color_schemes ~w(dark light)

  schema "scenes" do
    field :name, :string
    field :mode, :string, default: "dashboard"
    has_many :widget_instances, Kakemono.Widgets.Instance, on_delete: :delete_all

    # layout shape (dashboard): %{"cells" => [%{"widget_instance_id" => 1, "x" => 0, "y" => 0, "w" => 6, "h" => 4}, ...]}
    # layout shape (fullscreen_widget): %{"widget_instance_id" => 1}
    field :layout, :map, default: %{"cells" => []}
    # schedule (nullable): %{"days" => [1..7], "start_hour" => 0..23, "end_hour" => 0..23}
    field :schedule, :map
    field :aspect_ratio, :string, default: "16:9"
    field :orientation, :string, default: "portrait"
    field :color_scheme, :string, default: "light"
    timestamps()
  end

  def modes, do: @modes
  def aspect_ratios, do: @aspect_ratios
  def orientations, do: @orientations
  def color_schemes, do: @color_schemes

  def changeset(p, attrs) do
    p
    |> cast(attrs, [:name, :mode, :layout, :schedule, :aspect_ratio, :orientation, :color_scheme])
    |> validate_required([:name, :mode, :layout])
    |> validate_inclusion(:mode, @modes)
    |> validate_inclusion(:aspect_ratio, @aspect_ratios)
    |> validate_inclusion(:orientation, @orientations)
    |> validate_inclusion(:color_scheme, @color_schemes)
    |> validate_layout()
    |> validate_schedule()
  end

  defp validate_layout(changeset) do
    case {get_field(changeset, :mode), get_field(changeset, :layout)} do
      {"dashboard", %{"cells" => cells}} when is_list(cells) ->
        if Enum.all?(cells, &valid_cell?/1) do
          changeset
        else
          add_error(
            changeset,
            :layout,
            "invalid cell (need widget_instance_id, x, y, w, h with x+w<=12, y+h<=12, and positive sizes)"
          )
        end

      {"dashboard", _} ->
        add_error(changeset, :layout, ~s(must be %{"cells" => [...]} in dashboard mode))

      {"fullscreen_widget", %{"widget_instance_id" => id}} when is_integer(id) ->
        changeset

      {"fullscreen_widget", _} ->
        add_error(
          changeset,
          :layout,
          ~s(must be %{"widget_instance_id" => id} in fullscreen_widget mode)
        )

      _ ->
        changeset
    end
  end

  defp valid_cell?(%{"widget_instance_id" => id, "x" => x, "y" => y, "w" => w, "h" => h})
       when is_integer(id) and is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h) do
    x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= 12 and y + h <= 12
  end

  defp valid_cell?(_), do: false

  defp validate_schedule(changeset) do
    case get_field(changeset, :schedule) do
      nil ->
        changeset

      %{"days" => days, "start_hour" => sh, "end_hour" => eh}
      when is_list(days) and is_integer(sh) and is_integer(eh) ->
        cond do
          days == [] ->
            add_error(changeset, :schedule, "must select at least one day")

          not Enum.all?(days, &(is_integer(&1) and &1 in 1..7)) ->
            add_error(changeset, :schedule, "days must be integers in 1..7")

          sh not in 0..23 or eh not in 0..23 ->
            add_error(changeset, :schedule, "start_hour/end_hour must be in 0..23")

          true ->
            changeset
        end

      _ ->
        add_error(
          changeset,
          :schedule,
          ~s(must be nil or %{"days" => [...], "start_hour" => N, "end_hour" => N})
        )
    end
  end
end
