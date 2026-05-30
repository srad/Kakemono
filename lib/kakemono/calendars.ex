defmodule Kakemono.Calendars do
  @moduledoc "Managed calendars and recurring events for calendar widgets."

  import Ecto.Query

  alias Kakemono.Calendars.{Calendar, Event}
  alias Kakemono.{Displays, Repo}

  @pubsub Kakemono.PubSub
  @next_occurrence_horizon_days 366 * 3
  @seconds_per_day 86_400
  @widget_view_modes ~w(agenda week two_week month)
  @weekday_labels ~w(Mon Tue Wed Thu Fri Sat Sun)

  def list, do: list_calendars()

  def list_calendars do
    Repo.all(from c in Calendar, order_by: [asc: c.name, asc: c.id])
  end

  def get(id), do: Repo.get(Calendar, id)
  def get!(id), do: Repo.get!(Calendar, id)

  def get_with_events(id) do
    case Repo.get(Calendar, id) do
      nil ->
        nil

      calendar ->
        Repo.preload(
          calendar,
          events: from(e in Event, order_by: [asc: e.starts_at_utc, asc: e.id])
        )
    end
  end

  def create(attrs), do: create_calendar(attrs)

  def create_calendar(attrs) do
    with {:ok, calendar} <- %Calendar{} |> Calendar.changeset(attrs) |> Repo.insert() do
      broadcast_updated(calendar.id)
      {:ok, calendar}
    end
  end

  def update_calendar(%Calendar{} = calendar, attrs) do
    with {:ok, updated} <- calendar |> Calendar.changeset(attrs) |> Repo.update() do
      broadcast_updated(updated.id)
      {:ok, updated}
    end
  end

  def delete_calendar(%Calendar{} = calendar) do
    with {:ok, deleted} <- Repo.delete(calendar) do
      broadcast_updated(deleted.id)
      {:ok, deleted}
    end
  end

  def list_events(calendar_id) do
    Repo.all(
      from e in Event,
        where: e.calendar_id == ^calendar_id,
        order_by: [asc: e.starts_at_utc, asc: e.id]
    )
  end

  def get_event(id) do
    case Repo.get(Event, id) do
      nil -> nil
      event -> Repo.preload(event, :calendar)
    end
  end

  def get_event!(id), do: Event |> Repo.get!(id) |> Repo.preload(:calendar)

  def create_event(%Calendar{} = calendar, attrs) do
    with {:ok, normalized} <- normalize_event_attrs(calendar, attrs),
         {:ok, event} <-
           %Event{}
           |> Event.changeset(Map.put(normalized, :calendar_id, calendar.id))
           |> Repo.insert() do
      broadcast_updated(calendar.id)
      {:ok, event}
    end
  end

  def update_event(%Event{} = event, attrs) do
    event = Repo.preload(event, :calendar)
    calendar = event.calendar

    with {:ok, normalized} <- normalize_event_attrs(calendar, attrs),
         {:ok, updated} <-
           event
           |> Event.changeset(Map.put(normalized, :calendar_id, calendar.id))
           |> Repo.update() do
      broadcast_updated(calendar.id)
      {:ok, updated}
    end
  end

  def delete_event(%Event{} = event) do
    event = Repo.preload(event, :calendar)

    with {:ok, deleted} <- Repo.delete(event) do
      broadcast_updated(event.calendar_id)
      {:ok, deleted}
    end
  end

  def list_event_rows(calendar_id, now_utc \\ now_utc()) do
    case get_with_events(calendar_id) do
      nil ->
        []

      calendar ->
        calendar.events
        |> Enum.map(fn event ->
          %{
            event: event,
            next_occurrence: next_occurrence(event, calendar.timezone, now_utc),
            recurrence_summary: recurrence_summary(event)
          }
        end)
        |> Enum.sort_by(fn row ->
          case row.next_occurrence do
            nil -> {1, 0}
            occurrence -> {0, DateTime.to_unix(occurrence.start_at)}
          end
        end)
    end
  end

  def list_occurrences(calendar_id, from_utc, to_utc, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    case get_with_events(calendar_id) do
      nil ->
        []

      calendar ->
        calendar.events
        |> Enum.flat_map(&occurrences_for_event(&1, calendar.timezone, from_utc, to_utc))
        |> Enum.sort_by(&DateTime.to_unix(&1.start_at))
        |> limit_occurrences(limit)
    end
  end

  def widget_view(calendar_id, view_mode, now_utc \\ now_utc(), opts \\ []) do
    case get(calendar_id) do
      nil ->
        nil

      calendar ->
        case normalize_widget_view_mode(view_mode) do
          "agenda" -> agenda_widget_view(calendar, now_utc, opts)
          mode -> grid_widget_view(calendar, mode, now_utc)
        end
    end
  end

  def next_occurrence(%Event{} = event, timezone, now_utc \\ now_utc()) do
    horizon = DateTime.add(now_utc, @next_occurrence_horizon_days * @seconds_per_day, :second)

    occurrences_for_event(event, timezone, now_utc, horizon, limit: 1)
    |> List.first()
  end

  defp agenda_widget_view(calendar, now_utc, opts) do
    lookahead_days = Keyword.get(opts, :lookahead_days, 14)
    max_items = Keyword.get(opts, :max_items, 5)

    occurrences =
      list_occurrences(
        calendar.id,
        now_utc,
        DateTime.add(now_utc, lookahead_days * @seconds_per_day, :second),
        limit: max_items
      )

    %{
      calendar: calendar,
      view_mode: "agenda",
      label: agenda_range_label(lookahead_days),
      today: local_today(calendar.timezone, now_utc),
      occurrences: occurrences
    }
  end

  defp grid_widget_view(calendar, view_mode, now_utc) do
    today = local_today(calendar.timezone, now_utc)
    range = grid_range(view_mode, today)

    {from_utc, to_utc} =
      local_date_window_utc(range.grid_start, range.grid_end, calendar.timezone)

    buckets =
      calendar.id
      |> list_occurrences(from_utc, to_utc, limit: :infinity)
      |> bucket_occurrences()

    days =
      range.grid_start
      |> dates_between(range.grid_end)
      |> Enum.map(fn date ->
        occurrences = Map.get(buckets, date, [])

        %{
          date: date,
          in_range:
            Date.compare(date, range.range_start) != :lt and
              Date.compare(date, range.range_end) != :gt,
          is_today: date == today,
          event_count: length(occurrences),
          visible_occurrences: Enum.take(occurrences, range.visible_limit),
          overflow_count: max(length(occurrences) - range.visible_limit, 0)
        }
      end)

    %{
      calendar: calendar,
      view_mode: view_mode,
      label: range.label,
      today: today,
      weekday_labels: @weekday_labels,
      weeks: Enum.chunk_every(days, 7)
    }
  end

  def recurrence_summary(%Event{} = event) do
    interval = max(event.recurrence_interval || 1, 1)

    base =
      case event.recurrence do
        "daily" when interval == 1 -> "Daily"
        "daily" -> "Every #{interval} days"
        "weekly" -> weekly_summary(event, interval)
        "monthly" when interval == 1 -> "Monthly"
        "monthly" -> "Every #{interval} months"
        "yearly" when interval == 1 -> "Yearly"
        "yearly" -> "Every #{interval} years"
        _ -> "Once"
      end

    case event.recurrence_until_date do
      %Date{} = until_date -> "#{base} until #{Date.to_iso8601(until_date)}"
      _ -> base
    end
  end

  def now_utc do
    case Application.get_env(:kakemono, :calendar_now_fn, &DateTime.utc_now/0).() do
      %DateTime{} = now ->
        DateTime.shift_zone!(now, "Etc/UTC")

      %NaiveDateTime{} = now ->
        DateTime.from_naive!(now, "Etc/UTC")
    end
  end

  defp occurrences_for_event(event, timezone, from_utc, to_utc, opts \\ []) do
    limit = Keyword.get(opts, :limit, :infinity)
    base_local_start = DateTime.shift_zone!(event.starts_at_utc, timezone)
    base_local_end = event.ends_at_utc && DateTime.shift_zone!(event.ends_at_utc, timezone)
    base_date = DateTime.to_date(base_local_start)
    start_time = base_local_start |> DateTime.to_naive() |> NaiveDateTime.to_time()
    local_from_date = Date.add(DateTime.shift_zone!(from_utc, timezone) |> DateTime.to_date(), -1)
    local_to_date = Date.add(DateTime.shift_zone!(to_utc, timezone) |> DateTime.to_date(), 1)

    local_end_delta =
      cond do
        base_local_end ->
          NaiveDateTime.diff(
            DateTime.to_naive(base_local_end),
            DateTime.to_naive(base_local_start),
            :second
          )

        event.all_day ->
          @seconds_per_day

        true ->
          nil
      end

    dates_between(local_from_date, local_to_date)
    |> Enum.reduce_while([], fn date, acc ->
      acc =
        if recurring_on_date?(event, date, base_date) do
          occurrence = build_occurrence(event, timezone, date, start_time, local_end_delta)

          if occurrence && overlaps_window?(occurrence, from_utc, to_utc),
            do: [occurrence | acc],
            else: acc
        else
          acc
        end

      if limit != :infinity and length(acc) >= limit do
        {:halt, acc}
      else
        {:cont, acc}
      end
    end)
    |> Enum.reverse()
  end

  defp build_occurrence(event, timezone, date, start_time, local_end_delta) do
    with {:ok, start_naive} <- NaiveDateTime.new(date, start_time),
         {:ok, start_local} <- local_datetime(start_naive, timezone) do
      end_local =
        if is_integer(local_end_delta) do
          end_naive = NaiveDateTime.add(start_naive, local_end_delta, :second)

          case local_datetime(end_naive, timezone) do
            {:ok, local} -> local
            {:error, _reason} -> nil
          end
        end

      start_at = DateTime.shift_zone!(start_local, "Etc/UTC")
      end_at = if end_local, do: DateTime.shift_zone!(end_local, "Etc/UTC")

      %{
        calendar_id: event.calendar_id,
        event_id: event.id,
        title: event.title,
        location: event.location,
        notes: event.notes,
        all_day: event.all_day,
        start_at: start_at,
        end_at: end_at,
        local_start: start_local,
        local_end: end_local,
        recurrence: event.recurrence
      }
    end
  end

  defp normalize_widget_view_mode(view_mode) when view_mode in @widget_view_modes, do: view_mode
  defp normalize_widget_view_mode(_), do: "two_week"

  defp limit_occurrences(occurrences, :infinity), do: occurrences
  defp limit_occurrences(occurrences, nil), do: occurrences
  defp limit_occurrences(occurrences, limit), do: Enum.take(occurrences, limit)

  defp agenda_range_label(1), do: "Next day"
  defp agenda_range_label(days), do: "Next #{days} days"

  defp local_today(timezone, now_utc) do
    now_utc
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
  end

  defp grid_range("week", today) do
    range_start = week_anchor(today)
    range_end = Date.add(range_start, 6)

    %{
      range_start: range_start,
      range_end: range_end,
      grid_start: range_start,
      grid_end: range_end,
      label: date_range_label(range_start, range_end),
      visible_limit: 2
    }
  end

  defp grid_range("two_week", today) do
    range_start = week_anchor(today)
    range_end = Date.add(range_start, 13)

    %{
      range_start: range_start,
      range_end: range_end,
      grid_start: range_start,
      grid_end: range_end,
      label: date_range_label(range_start, range_end),
      visible_limit: 2
    }
  end

  defp grid_range("month", today) do
    {:ok, month_start} = Date.new(today.year, today.month, 1)
    month_end = shift_month(month_start, 1) |> Date.add(-1)
    grid_start = week_anchor(month_start)
    grid_end = week_end(month_end)

    %{
      range_start: month_start,
      range_end: month_end,
      grid_start: grid_start,
      grid_end: grid_end,
      label: Elixir.Calendar.strftime(month_start, "%B %Y"),
      visible_limit: 1
    }
  end

  defp local_date_window_utc(start_date, end_date, timezone) do
    {:ok, start_naive} = NaiveDateTime.new(start_date, ~T[00:00:00])
    {:ok, end_naive} = NaiveDateTime.new(Date.add(end_date, 1), ~T[00:00:00])
    {:ok, start_local} = local_datetime(start_naive, timezone)
    {:ok, end_local} = local_datetime(end_naive, timezone)

    {
      DateTime.shift_zone!(start_local, "Etc/UTC"),
      DateTime.shift_zone!(end_local, "Etc/UTC")
    }
  end

  defp bucket_occurrences(occurrences) do
    occurrences
    |> Enum.reduce(%{}, fn occurrence, buckets ->
      occurrence
      |> occurrence_dates()
      |> Enum.reduce(buckets, fn date, acc ->
        Map.update(acc, date, [occurrence], &[occurrence | &1])
      end)
    end)
    |> Map.new(fn {date, items} ->
      {date, Enum.sort_by(items, &occurrence_sort_key/1)}
    end)
  end

  defp occurrence_dates(%{local_start: local_start, local_end: nil}) do
    [DateTime.to_date(local_start)]
  end

  defp occurrence_dates(%{local_start: local_start, local_end: local_end}) do
    start_date = DateTime.to_date(local_start)
    end_date = occurrence_last_local_date(local_start, local_end)
    dates_between(start_date, end_date)
  end

  defp occurrence_last_local_date(local_start, local_end) do
    start_date = DateTime.to_date(local_start)
    end_date = DateTime.to_date(local_end)
    end_time = DateTime.to_time(local_end)

    if Time.compare(end_time, ~T[00:00:00]) == :eq and Date.compare(end_date, start_date) == :gt do
      Date.add(end_date, -1)
    else
      end_date
    end
  end

  defp occurrence_sort_key(occurrence) do
    {
      DateTime.to_unix(occurrence.start_at),
      if(occurrence.all_day, do: 0, else: 1),
      String.downcase(occurrence.title)
    }
  end

  defp date_range_label(start_date, end_date) do
    cond do
      start_date.year == end_date.year and start_date.month == end_date.month ->
        "#{Elixir.Calendar.strftime(start_date, "%b")} #{start_date.day} - #{end_date.day}"

      start_date.year == end_date.year ->
        "#{Elixir.Calendar.strftime(start_date, "%b")} #{start_date.day} - " <>
          "#{Elixir.Calendar.strftime(end_date, "%b")} #{end_date.day}"

      true ->
        "#{Elixir.Calendar.strftime(start_date, "%b")} #{start_date.day}, #{start_date.year} - " <>
          "#{Elixir.Calendar.strftime(end_date, "%b")} #{end_date.day}, #{end_date.year}"
    end
  end

  defp overlaps_window?(occurrence, from_utc, to_utc) do
    if occurrence.end_at do
      DateTime.compare(occurrence.end_at, from_utc) == :gt and
        DateTime.compare(occurrence.start_at, to_utc) == :lt
    else
      DateTime.compare(occurrence.start_at, from_utc) != :lt and
        DateTime.compare(occurrence.start_at, to_utc) == :lt
    end
  end

  defp recurring_on_date?(event, candidate_date, base_date) do
    interval = max(event.recurrence_interval || 1, 1)

    cond do
      Date.compare(candidate_date, base_date) == :lt ->
        false

      match?(%Date{}, event.recurrence_until_date) and
          Date.compare(candidate_date, event.recurrence_until_date) == :gt ->
        false

      event.recurrence == "daily" ->
        rem(Date.diff(candidate_date, base_date), interval) == 0

      event.recurrence == "weekly" ->
        weekly_occurrence?(event, candidate_date, base_date, interval)

      event.recurrence == "monthly" ->
        monthly_occurrence?(candidate_date, base_date, interval)

      event.recurrence == "yearly" ->
        yearly_occurrence?(candidate_date, base_date, interval)

      true ->
        candidate_date == base_date
    end
  end

  defp weekly_occurrence?(event, candidate_date, base_date, interval) do
    weekdays = Event.recurrence_weekdays(event)
    base_anchor = week_anchor(base_date)
    candidate_anchor = week_anchor(candidate_date)
    week_offset = div(Date.diff(candidate_anchor, base_anchor), 7)

    Date.day_of_week(candidate_date) in weekdays and
      week_offset >= 0 and
      rem(week_offset, interval) == 0
  end

  defp monthly_occurrence?(candidate_date, base_date, interval) do
    month_offset = months_between(base_date, candidate_date)

    month_offset >= 0 and rem(month_offset, interval) == 0 and
      candidate_date == shift_month(base_date, month_offset)
  end

  defp yearly_occurrence?(candidate_date, base_date, interval) do
    year_offset = candidate_date.year - base_date.year

    year_offset >= 0 and rem(year_offset, interval) == 0 and
      candidate_date == shift_year(base_date, year_offset)
  end

  defp shift_month(base_date, offset) do
    month_index = base_date.month - 1 + offset
    year = base_date.year + div(month_index, 12)
    month = rem(month_index, 12) + 1
    day = min(base_date.day, days_in_month(year, month))
    {:ok, date} = Date.new(year, month, day)
    date
  end

  defp shift_year(base_date, offset) do
    year = base_date.year + offset
    day = min(base_date.day, days_in_month(year, base_date.month))
    {:ok, date} = Date.new(year, base_date.month, day)
    date
  end

  defp days_in_month(year, month) do
    {:ok, date} = Date.new(year, month, 1)
    Date.days_in_month(date)
  end

  defp months_between(base_date, candidate_date) do
    (candidate_date.year - base_date.year) * 12 + candidate_date.month - base_date.month
  end

  defp week_anchor(date), do: Date.add(date, 1 - Date.day_of_week(date))
  defp week_end(date), do: Date.add(week_anchor(date), 6)

  defp dates_between(start_date, end_date) do
    if Date.compare(start_date, end_date) == :gt do
      []
    else
      for offset <- 0..Date.diff(end_date, start_date), do: Date.add(start_date, offset)
    end
  end

  defp local_datetime(naive, timezone) do
    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _second} -> {:ok, first}
      {:gap, _before, gap_end} -> {:ok, gap_end}
      {:error, reason} -> {:error, reason}
    end
  end

  defp weekly_summary(event, interval) do
    weekdays =
      event
      |> Event.recurrence_weekdays()
      |> Enum.map(&weekday_label/1)
      |> Enum.join(", ")

    prefix = if interval == 1, do: "Weekly", else: "Every #{interval} weeks"
    if weekdays == "", do: prefix, else: "#{prefix} on #{weekdays}"
  end

  defp weekday_label(1), do: "Mon"
  defp weekday_label(2), do: "Tue"
  defp weekday_label(3), do: "Wed"
  defp weekday_label(4), do: "Thu"
  defp weekday_label(5), do: "Fri"
  defp weekday_label(6), do: "Sat"
  defp weekday_label(7), do: "Sun"

  defp normalize_event_attrs(calendar, attrs) do
    all_day = truthy?(param(attrs, "all_day"))

    with {:ok, title} <- required_string(attrs, "title"),
         {:ok, start_on} <- required_date(attrs, "start_on"),
         {:ok, start_time} <- parse_start_time(attrs, all_day),
         {:ok, end_on} <- optional_date(attrs, "end_on"),
         {:ok, end_time} <- parse_end_time(attrs, all_day, end_on),
         {:ok, recurrence} <- recurrence_value(attrs),
         {:ok, recurrence_interval} <- positive_integer(attrs, "recurrence_interval", 1),
         {:ok, recurrence_until_date} <- optional_date(attrs, "recurrence_until_date"),
         :ok <- validate_until_date(start_on, recurrence_until_date),
         {:ok, starts_at_utc} <-
           start_datetime_utc(calendar.timezone, start_on, start_time, all_day),
         {:ok, ends_at_utc} <-
           end_datetime_utc(calendar.timezone, start_on, end_on, end_time, all_day),
         :ok <- validate_end_datetimes(starts_at_utc, ends_at_utc),
         {:ok, recurrence_weekdays} <- recurrence_weekdays(attrs, recurrence, start_on) do
      {:ok,
       %{
         title: title,
         starts_at_utc: starts_at_utc,
         ends_at_utc: ends_at_utc,
         all_day: all_day,
         location: blank_to_nil(param(attrs, "location")),
         notes: blank_to_nil(param(attrs, "notes")),
         recurrence: recurrence,
         recurrence_interval: recurrence_interval,
         recurrence_weekdays: Enum.join(recurrence_weekdays, ","),
         recurrence_until_date: recurrence_until_date
       }}
    end
  end

  defp required_string(attrs, key) do
    case param(attrs, key) |> to_string_or_nil() |> blank_to_nil() do
      nil -> {:error, invalid_changeset(%{key => "can't be blank"})}
      value -> {:ok, value}
    end
  end

  defp required_date(attrs, key) do
    case optional_date(attrs, key) do
      {:ok, nil} -> {:error, invalid_changeset(%{key => "can't be blank"})}
      other -> other
    end
  end

  defp optional_date(attrs, key) do
    case param(attrs, key) |> to_string_or_nil() |> blank_to_nil() do
      nil ->
        {:ok, nil}

      value ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          {:error, _} -> {:error, invalid_changeset(%{key => "is invalid"})}
        end
    end
  end

  defp parse_start_time(_attrs, true), do: {:ok, nil}

  defp parse_start_time(attrs, false) do
    case parse_time(param(attrs, "start_time")) do
      {:ok, nil} -> {:error, invalid_changeset(%{"start_time" => "can't be blank"})}
      other -> other
    end
  end

  defp parse_end_time(_attrs, true, _end_on), do: {:ok, nil}

  defp parse_end_time(attrs, false, end_on) do
    case parse_time(param(attrs, "end_time")) do
      {:ok, nil} when is_nil(end_on) ->
        {:ok, nil}

      {:ok, nil} ->
        {:error, invalid_changeset(%{"end_time" => "can't be blank"})}

      other ->
        other
    end
  end

  defp parse_time(nil), do: {:ok, nil}

  defp parse_time(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      trimmed ->
        case Time.from_iso8601(trimmed <> ":00") do
          {:ok, time} -> {:ok, time}
          {:error, _} -> {:error, invalid_changeset(%{"time" => "is invalid"})}
        end
    end
  end

  defp recurrence_value(attrs) do
    recurrence = param(attrs, "recurrence") |> to_string_or_nil() || "none"

    if recurrence in Event.recurrence_values() do
      {:ok, recurrence}
    else
      {:error, invalid_changeset(%{"recurrence" => "is invalid"})}
    end
  end

  defp positive_integer(attrs, key, default) do
    case param(attrs, key) |> to_string_or_nil() |> blank_to_nil() do
      nil ->
        {:ok, default}

      value ->
        case Integer.parse(value) do
          {number, ""} when number >= 1 -> {:ok, number}
          _ -> {:error, invalid_changeset(%{key => "must be a positive integer"})}
        end
    end
  end

  defp validate_until_date(_start_on, nil), do: :ok

  defp validate_until_date(start_on, %Date{} = until_date) do
    if Date.compare(until_date, start_on) == :lt do
      {:error,
       invalid_changeset(%{"recurrence_until_date" => "must be on or after the start date"})}
    else
      :ok
    end
  end

  defp start_datetime_utc(timezone, start_on, _start_time, true) do
    with {:ok, naive} <- NaiveDateTime.new(start_on, ~T[00:00:00]),
         {:ok, local} <- local_datetime(naive, timezone) do
      {:ok, DateTime.shift_zone!(local, "Etc/UTC")}
    end
  end

  defp start_datetime_utc(timezone, start_on, start_time, false) do
    with {:ok, naive} <- NaiveDateTime.new(start_on, start_time),
         {:ok, local} <- local_datetime(naive, timezone) do
      {:ok, DateTime.shift_zone!(local, "Etc/UTC")}
    end
  end

  defp end_datetime_utc(_timezone, _start_on, nil, nil, _all_day), do: {:ok, nil}

  defp end_datetime_utc(timezone, _start_on, %Date{} = end_on, _end_time, true) do
    with {:ok, naive} <- NaiveDateTime.new(Date.add(end_on, 1), ~T[00:00:00]),
         {:ok, local} <- local_datetime(naive, timezone) do
      {:ok, DateTime.shift_zone!(local, "Etc/UTC")}
    end
  end

  defp end_datetime_utc(timezone, start_on, end_on, nil, false),
    do: end_datetime_utc(timezone, start_on, end_on, ~T[00:00:00], false)

  defp end_datetime_utc(timezone, start_on, end_on, %Time{} = end_time, false) do
    target_date = end_on || start_on

    with {:ok, naive} <- NaiveDateTime.new(target_date, end_time),
         {:ok, local} <- local_datetime(naive, timezone) do
      {:ok, DateTime.shift_zone!(local, "Etc/UTC")}
    end
  end

  defp validate_end_datetimes(_start_at, nil), do: :ok

  defp validate_end_datetimes(start_at, end_at) do
    if DateTime.compare(end_at, start_at) == :gt do
      :ok
    else
      {:error, invalid_changeset(%{"end_on" => "must be after the start"})}
    end
  end

  defp recurrence_weekdays(attrs, "weekly", start_on) do
    weekdays =
      attrs
      |> param("recurrence_weekdays")
      |> List.wrap()
      |> Enum.map(&normalize_weekday/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok, if(weekdays == [], do: [Date.day_of_week(start_on)], else: weekdays)}
  end

  defp recurrence_weekdays(_attrs, _recurrence, _start_on), do: {:ok, []}

  defp normalize_weekday(value) when is_integer(value) and value in 1..7, do: value

  defp normalize_weekday(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {weekday, ""} when weekday in 1..7 -> weekday
      _ -> nil
    end
  end

  defp normalize_weekday(_), do: nil

  defp invalid_changeset(errors) do
    changeset =
      {%{}, %{}} |> Ecto.Changeset.cast(%{}, [])

    Enum.reduce(errors, changeset, fn {field, message}, acc ->
      Ecto.Changeset.add_error(acc, String.to_atom(field), message)
    end)
  end

  defp param(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value) when is_binary(value), do: value
  defp to_string_or_nil(value), do: to_string(value)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp truthy?(value) when value in [true, "true", "on", 1, "1"], do: true
  defp truthy?(_), do: false

  defp broadcast_updated(calendar_id) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "calendars",
      {:calendar_list_updated, %{calendar_id: calendar_id}}
    )

    Phoenix.PubSub.broadcast(
      @pubsub,
      "calendar:#{calendar_id}",
      {:calendar_updated, %{calendar_id: calendar_id}}
    )

    for display <- Displays.list() do
      Phoenix.PubSub.broadcast(
        @pubsub,
        "display:#{display.id}",
        {:calendar_updated, %{calendar_id: calendar_id}}
      )
    end

    :ok
  end
end
