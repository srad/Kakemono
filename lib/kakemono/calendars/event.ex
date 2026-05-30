defmodule Kakemono.Calendars.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @recurrence_values ~w(none daily weekly monthly yearly)

  schema "calendar_events" do
    field :title, :string
    field :starts_at_utc, :utc_datetime
    field :ends_at_utc, :utc_datetime
    field :all_day, :boolean, default: false
    field :location, :string
    field :notes, :string
    field :recurrence, :string, default: "none"
    field :recurrence_interval, :integer, default: 1
    field :recurrence_weekdays, :string, default: ""
    field :recurrence_until_date, :date
    belongs_to :calendar, Kakemono.Calendars.Calendar
    timestamps()
  end

  def recurrence_values, do: @recurrence_values

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :calendar_id,
      :title,
      :starts_at_utc,
      :ends_at_utc,
      :all_day,
      :location,
      :notes,
      :recurrence,
      :recurrence_interval,
      :recurrence_weekdays,
      :recurrence_until_date
    ])
    |> validate_required([:calendar_id, :title, :starts_at_utc, :all_day, :recurrence])
    |> update_change(:title, &String.trim/1)
    |> update_change(:location, &blank_to_nil/1)
    |> update_change(:notes, &blank_to_nil/1)
    |> update_change(:recurrence_weekdays, &normalize_weekdays_string/1)
    |> validate_inclusion(:recurrence, @recurrence_values)
    |> validate_number(:recurrence_interval,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 366
    )
    |> validate_weekdays()
    |> validate_end_after_start()
  end

  def recurrence_weekdays(%__MODULE__{recurrence_weekdays: value}) do
    parse_weekdays(value)
  end

  defp validate_weekdays(changeset) do
    case get_field(changeset, :recurrence_weekdays) |> parse_weekdays() do
      [] ->
        changeset

      weekdays ->
        if Enum.all?(weekdays, &(&1 in 1..7)) do
          changeset
        else
          add_error(changeset, :recurrence_weekdays, "must use weekdays 1..7")
        end
    end
  end

  defp validate_end_after_start(changeset) do
    start_at = get_field(changeset, :starts_at_utc)
    end_at = get_field(changeset, :ends_at_utc)

    if start_at && end_at && DateTime.compare(end_at, start_at) != :gt do
      add_error(changeset, :ends_at_utc, "must be after the start")
    else
      changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_weekdays_string(nil), do: ""

  defp normalize_weekdays_string(value) when is_binary(value) do
    value
    |> parse_weekdays()
    |> Enum.join(",")
  end

  defp normalize_weekdays_string(values) when is_list(values) do
    values
    |> Enum.map(&normalize_weekday/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp parse_weekdays(nil), do: []
  defp parse_weekdays(""), do: []

  defp parse_weekdays(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&normalize_weekday/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_weekdays(values) when is_list(values) do
    values
    |> Enum.map(&normalize_weekday/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_weekday(value) when is_integer(value) and value in 1..7, do: value

  defp normalize_weekday(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {weekday, ""} when weekday in 1..7 -> weekday
      _ -> nil
    end
  end

  defp normalize_weekday(_), do: nil
end
