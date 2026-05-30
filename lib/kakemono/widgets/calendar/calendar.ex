defmodule Kakemono.Widgets.Calendar do
  use Kakemono.Widget

  alias Kakemono.Calendars

  @view_modes ~w(agenda week two_week month)

  @impl true
  def type, do: "calendar"

  @impl true
  def name, do: "Calendar"

  @impl true
  def icon, do: "📅"

  @impl true
  def fields do
    [
      %{key: "calendar_id", label: "Calendar", type: :calendar_select, required: true},
      %{key: "title", label: "Title override", type: :text, required: false},
      %{
        key: "view_mode",
        label: "View",
        type: :select,
        required: false,
        default: "two_week",
        options: [
          {"week", "1 Week"},
          {"two_week", "2 Weeks"},
          {"month", "Month"},
          {"agenda", "Agenda"}
        ]
      },
      %{
        key: "max_items",
        label: "Agenda max items",
        type: :number,
        required: false,
        integer: true,
        min: 1,
        max: 20,
        step: "1",
        default: 5
      },
      %{
        key: "lookahead_days",
        label: "Agenda lookahead days",
        type: :number,
        required: false,
        integer: true,
        min: 1,
        max: 365,
        step: "1",
        default: 14
      },
      %{
        key: "show_location",
        label: "Show location in agenda",
        type: :checkbox,
        required: false,
        default: true
      },
      %{
        key: "show_header",
        label: "Show header",
        type: :checkbox,
        required: false,
        default: true
      },
      %{
        key: "show_agenda",
        label: "Show upcoming events sidebar",
        type: :checkbox,
        required: false,
        default: false
      }
    ]
  end

  @impl true
  def render(assigns) do
    config = assigns.instance.config || %{}
    view_mode = safe_view_mode(config["view_mode"])
    title_override = config["title"] |> blank_to_nil()
    max_items = config["max_items"] || 5
    lookahead_days = config["lookahead_days"] || 14
    show_location = Map.get(config, "show_location", true)
    show_header = Map.get(config, "show_header", true)
    show_agenda = Map.get(config, "show_agenda", false)
    now = Calendars.now_utc()

    {view, agenda_view} =
      case config["calendar_id"] do
        id when is_integer(id) ->
          v =
            Calendars.widget_view(
              id,
              view_mode,
              now,
              max_items: max_items,
              lookahead_days: lookahead_days
            )

          a =
            if show_agenda and view_mode != "agenda" and v do
              sidebar_occurrences(v.calendar, now, max_items, lookahead_days)
            end

          {v, a}

        _ ->
          {nil, nil}
      end

    calendar = view && view.calendar

    assigns =
      assigns
      |> Map.put(:view, view)
      |> Map.put(:sidebar_occurrences, agenda_view)
      |> Map.put(:view_mode, if(view, do: safe_view_mode(view.view_mode), else: view_mode))
      |> Map.put(:show_location, show_location)
      |> Map.put(:title, title_override || (calendar && calendar.name) || "Calendar")
      |> Map.put(:accent, (calendar && calendar.color) || "#38bdf8")
      |> Map.put(:show_header, show_header)
      |> Map.put(:now, now)
      |> Map.put(:lookahead_days, lookahead_days)

    ~H"""
    <div
      class={["kakemono-widget kakemono-widget-calendar", "kw-calendar-view-" <> @view_mode]}
      style={"--kw-calendar-accent: #{@accent}"}
    >
      <header :if={@show_header} class="kw-calendar-header">
        <div class="kw-calendar-heading">
          <p class="kw-calendar-kicker">{view_kicker(@view_mode)}</p>
          <h2 class="kw-calendar-title">{@title}</h2>
        </div>
        <p :if={@view} class="kw-calendar-range">{@view.label}</p>
      </header>

      <div :if={is_nil(@view)} class="kw-calendar-empty">
        Select a calendar in the widget settings.
      </div>

      <div :if={@view && @view.view_mode == "agenda"} class="kw-calendar-agenda">
        {agenda_list(assigns, @view.occurrences)}
      </div>

      <div
        :if={@view && @view.view_mode != "agenda"}
        class={["kw-calendar-body", @sidebar_occurrences && "kw-calendar-split"]}
      >
        <div class="kw-calendar-grid-shell">
          <div class="kw-calendar-weekdays">
            <span :for={label <- @view.weekday_labels} class="kw-calendar-weekday">{label}</span>
          </div>

          <div class="kw-calendar-grid" style={"--kw-calendar-weeks: #{length(@view.weeks)}"}>
            <div :for={week <- @view.weeks} class="kw-calendar-grid-row">
              <section
                :for={day <- week}
                class={[
                  "kw-calendar-day",
                  not day.in_range && "is-outside",
                  day.is_today && "is-today",
                  day.event_count > 0 && "has-events"
                ]}
              >
                <div class="kw-calendar-day-header">
                  <span class="kw-calendar-day-number">{day.date.day}</span>
                  <span :if={day.event_count > 0} class="kw-calendar-day-count">
                    {day.event_count}
                  </span>
                </div>

                <div class="kw-calendar-day-events">
                  <div
                    :for={occurrence <- day.visible_occurrences}
                    class={["kw-calendar-chip", occurrence.all_day && "is-all-day"]}
                  >
                    <span class="kw-calendar-chip-time">
                      {day_occurrence_label(occurrence, day.date)}
                    </span>
                    <span class="kw-calendar-chip-title">{occurrence.title}</span>
                  </div>

                  <div :if={day.overflow_count > 0} class="kw-calendar-overflow">
                    +{day.overflow_count} more
                  </div>
                </div>
              </section>
            </div>
          </div>
        </div>

        <aside :if={@sidebar_occurrences} class="kw-calendar-sidebar">
          <p class="kw-calendar-sidebar-heading">Upcoming</p>
          {agenda_list(assigns, @sidebar_occurrences)}
        </aside>
      </div>
    </div>
    """
  end

  defp agenda_list(assigns, occurrences) do
    assigns = Map.put(assigns, :occurrences, occurrences)

    ~H"""
    <div :if={@occurrences == []} class="kw-calendar-empty kw-calendar-empty-inline">
      No events in the next {@lookahead_days} days.
    </div>

    <ul :if={@occurrences != []} class="kw-calendar-agenda-list">
      <li :for={occurrence <- @occurrences} class="kw-calendar-agenda-item">
        <div class="kw-calendar-agenda-main">
          <div class="kw-calendar-agenda-row">
            <span :if={occurrence_badge(occurrence, @now)} class="kw-calendar-badge">
              {occurrence_badge(occurrence, @now)}
            </span>
            <span class="kw-calendar-event-title">{occurrence.title}</span>
          </div>
          <div class="kw-calendar-agenda-meta">
            <span class="kw-calendar-event-meta">{occurrence_meta(occurrence)}</span>
            <span
              :if={@show_location and present?(occurrence.location)}
              class="kw-calendar-location"
            >
              {occurrence.location}
            </span>
          </div>
        </div>
      </li>
    </ul>
    """
  end

  defp sidebar_occurrences(calendar, now_utc, max_items, lookahead_days) do
    today = now_utc |> DateTime.shift_zone!(calendar.timezone) |> DateTime.to_date()
    {:ok, start_naive} = NaiveDateTime.new(today, ~T[00:00:00])

    from_utc =
      case DateTime.from_naive(start_naive, calendar.timezone) do
        {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
        {:ambiguous, first, _} -> DateTime.shift_zone!(first, "Etc/UTC")
        {:gap, _, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
      end

    to_utc = DateTime.add(now_utc, lookahead_days * 86_400, :second)

    Calendars.list_occurrences(calendar.id, from_utc, to_utc, limit: max_items)
  end

  defp safe_view_mode(view_mode) when view_mode in @view_modes, do: view_mode
  defp safe_view_mode(_), do: "two_week"

  defp view_kicker("agenda"), do: "Upcoming"
  defp view_kicker(_), do: "Calendar"

  defp occurrence_badge(occurrence, now) do
    if ongoing?(occurrence, now), do: "Now"
  end

  defp occurrence_meta(occurrence) do
    date_text = Calendar.strftime(occurrence.local_start, "%a, %b %-d")

    cond do
      occurrence.all_day ->
        "#{date_text} • All day"

      occurrence.local_end ->
        time_text =
          Calendar.strftime(occurrence.local_start, "%H:%M") <>
            " - " <> Calendar.strftime(occurrence.local_end, "%H:%M")

        "#{date_text} • #{time_text}"

      true ->
        "#{date_text} • #{Calendar.strftime(occurrence.local_start, "%H:%M")}"
    end
  end

  defp day_occurrence_label(occurrence, date) do
    cond do
      occurrence.all_day ->
        "All day"

      is_nil(occurrence.local_end) ->
        Calendar.strftime(occurrence.local_start, "%H:%M")

      Date.compare(date, DateTime.to_date(occurrence.local_start)) == :lt ->
        "Continues"

      Date.compare(date, DateTime.to_date(occurrence.local_start)) == :gt and
          Date.compare(date, DateTime.to_date(occurrence.local_end)) == :lt ->
        "Continues"

      Date.compare(date, DateTime.to_date(occurrence.local_start)) == :gt ->
        "Until #{Calendar.strftime(occurrence.local_end, "%H:%M")}"

      Date.compare(
        DateTime.to_date(occurrence.local_start),
        DateTime.to_date(occurrence.local_end)
      ) ==
          :eq ->
        Calendar.strftime(occurrence.local_start, "%H:%M")

      true ->
        "Starts #{Calendar.strftime(occurrence.local_start, "%H:%M")}"
    end
  end

  defp ongoing?(occurrence, now) do
    if occurrence.end_at do
      DateTime.compare(occurrence.start_at, now) != :gt and
        DateTime.compare(occurrence.end_at, now) == :gt
    else
      false
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
