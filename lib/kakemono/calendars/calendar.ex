defmodule Kakemono.Calendars.Calendar do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kakemono.TimeZones

  schema "calendars" do
    field :name, :string
    field :timezone, :string, default: "Etc/UTC"
    field :color, :string
    has_many :events, Kakemono.Calendars.Event, preload_order: [asc: :starts_at_utc]
    timestamps()
  end

  def changeset(calendar, attrs) do
    calendar
    |> cast(attrs, [:name, :timezone, :color])
    |> validate_required([:name, :timezone])
    |> validate_change(:timezone, fn :timezone, value ->
      if TimeZones.valid?(value), do: [], else: [timezone: "is invalid"]
    end)
    |> update_change(:name, &String.trim/1)
    |> update_change(:color, &normalize_color/1)
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{6}$/, message: "must be a hex color like #0f172a")
  end

  defp normalize_color(nil), do: nil

  defp normalize_color(color) when is_binary(color) do
    color
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> String.downcase(trimmed)
    end
  end
end
