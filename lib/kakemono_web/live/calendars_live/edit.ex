defmodule KakemonoWeb.CalendarsLive.Edit do
  use KakemonoWeb, :live_view

  alias Kakemono.Calendars

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Calendars.get_with_events(id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/c/calendars")}

      calendar ->
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(Kakemono.PubSub, "calendar:#{calendar.id}")

        {:ok,
         socket
         |> load(calendar)
         |> reset_event_form()}
    end
  end

  @impl true
  def handle_event("save_settings", %{"calendar" => params}, socket) do
    case Calendars.update_calendar(socket.assigns.calendar, params) do
      {:ok, calendar} ->
        {:noreply,
         socket
         |> load(calendar)
         |> put_flash(:info, "Settings saved")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("save_event", %{"event" => params}, socket) do
    params = compose_time_params(params)

    result =
      case socket.assigns.editing_event_id do
        nil ->
          Calendars.create_event(socket.assigns.calendar, params)

        id ->
          id |> Calendars.get_event!() |> Calendars.update_event(params)
      end

    case result do
      {:ok, _event} ->
        {:noreply,
         socket
         |> reload()
         |> reset_event_form()
         |> put_flash(:info, "Event saved")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("form_changed", %{"event" => params}, socket) do
    current = socket.assigns.event_form

    merged =
      current
      |> Map.merge(params, fn
        "recurrence_weekdays", _old, new -> List.wrap(new)
        _key, _old, new -> new
      end)
      |> derive_form_state(current)

    {:noreply, assign(socket, :event_form, merged)}
  end

  def handle_event("edit_event", %{"id" => id}, socket) do
    event = Calendars.get_event!(id)

    {:noreply,
     socket
     |> assign(:editing_event_id, event.id)
     |> assign(:event_form, event_form_from_event(event, socket.assigns.calendar.timezone))}
  end

  def handle_event("cancel_event_edit", _params, socket) do
    {:noreply, reset_event_form(socket)}
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    event = Calendars.get_event!(id)
    {:ok, _} = Calendars.delete_event(event)

    {:noreply,
     socket
     |> reload()
     |> reset_event_form()}
  end

  @impl true
  def handle_info({:calendar_updated, %{calendar_id: calendar_id}}, socket) do
    case Calendars.get_with_events(calendar_id) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/c/calendars")}

      calendar ->
        {:noreply, load(socket, calendar)}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <.link
            navigate={~p"/c/calendars"}
            class="inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-900"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Calendars
          </.link>
          <h1 class="mt-1 text-2xl font-semibold tracking-tight text-slate-950">
            {@calendar.name}
          </h1>
        </div>
        <p class="text-sm text-slate-500">{length(@calendar.events)} source events</p>
      </div>

      <form
        id="calendar-settings-form"
        phx-submit="save_settings"
        class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm"
      >
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-slate-950">Calendar settings</h2>
          <p class="text-sm text-slate-500">Timezone controls recurring event expansion.</p>
        </div>

        <div class="grid gap-4 md:grid-cols-3">
          <label class="block">
            <span class="mb-1 block text-sm font-medium text-slate-700">Name</span>
            <input
              type="text"
              name="calendar[name]"
              value={@calendar.name}
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            />
          </label>

          <label class="block">
            <span class="mb-1 block text-sm font-medium text-slate-700">Timezone</span>
            <select
              name="calendar[timezone]"
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
            >
              <option
                :for={timezone <- @timezones}
                value={timezone}
                selected={timezone == @calendar.timezone}
              >
                {timezone}
              </option>
            </select>
          </label>

          <label class="block">
            <span class="mb-1 block text-sm font-medium text-slate-700">Accent color</span>
            <input
              type="color"
              name="calendar[color]"
              value={@calendar.color || "#38bdf8"}
              class="h-10 w-full rounded-md border border-slate-300 bg-white p-1"
            />
          </label>
        </div>

        <button class="mt-4 inline-flex h-10 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800">
          Save settings
        </button>
      </form>

      <div class="grid gap-6 xl:grid-cols-[26rem_minmax(0,1fr)]">
        <section class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
          <div class="mb-4 flex items-start justify-between gap-4">
            <div>
              <h2 class="text-lg font-semibold text-slate-950">
                {if @editing_event_id, do: "Edit event", else: "Create event"}
              </h2>
              <p class="text-sm text-slate-500">
                Repeating yearly all-day events cover birthdays and anniversaries.
              </p>
            </div>
            <button
              :if={@editing_event_id}
              type="button"
              phx-click="cancel_event_edit"
              class="rounded-md border border-slate-200 px-3 py-1.5 text-sm font-medium text-slate-600 transition hover:bg-slate-50"
            >
              Cancel
            </button>
          </div>

          <form id="event-form" phx-submit="save_event" phx-change="form_changed" class="space-y-4">
            <label class="block">
              <span class="mb-1 block text-sm font-medium text-slate-700">Title</span>
              <input
                type="text"
                name="event[title]"
                value={@event_form["title"]}
                phx-debounce="300"
                class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
              />
            </label>

            <input type="hidden" name="event[all_day]" value="false" />
            <label class="flex items-center gap-2 text-sm font-medium text-slate-700">
              <input
                type="checkbox"
                name="event[all_day]"
                value="true"
                checked={truthy?(@event_form["all_day"])}
              /> All day
            </label>

            <div class={if truthy?(@event_form["all_day"]), do: "", else: "grid gap-4 sm:grid-cols-2"}>
              <label class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">
                  {if truthy?(@event_form["all_day"]), do: "Date", else: "Start date"}
                </span>
                <input
                  type="date"
                  name="event[start_on]"
                  value={@event_form["start_on"]}
                  class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                />
              </label>

              <div :if={not truthy?(@event_form["all_day"])} class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">Start time</span>
                <div class="flex items-center gap-1">
                  <select
                    name="event[start_hour]"
                    class="flex-1 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                  >
                    <option value="">--</option>
                    <option
                      :for={h <- hour_options()}
                      value={h}
                      selected={@event_form["start_hour"] == h}
                    >
                      {h}
                    </option>
                  </select>
                  <span class="text-slate-400">:</span>
                  <select
                    name="event[start_minute]"
                    class="flex-1 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                  >
                    <option value="">--</option>
                    <option
                      :for={m <- minute_options()}
                      value={m}
                      selected={@event_form["start_minute"] == m}
                    >
                      {m}
                    </option>
                  </select>
                </div>
              </div>
            </div>

            <div :if={not truthy?(@event_form["all_day"])} class="grid gap-4 sm:grid-cols-2">
              <label class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">End date</span>
                <input
                  type="date"
                  name="event[end_on]"
                  value={@event_form["end_on"]}
                  class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                />
              </label>

              <div class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">End time</span>
                <div class="flex items-center gap-1">
                  <select
                    name="event[end_hour]"
                    class="flex-1 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                  >
                    <option value="">--</option>
                    <option
                      :for={h <- hour_options()}
                      value={h}
                      selected={@event_form["end_hour"] == h}
                    >
                      {h}
                    </option>
                  </select>
                  <span class="text-slate-400">:</span>
                  <select
                    name="event[end_minute]"
                    class="flex-1 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                  >
                    <option value="">--</option>
                    <option
                      :for={m <- minute_options()}
                      value={m}
                      selected={@event_form["end_minute"] == m}
                    >
                      {m}
                    </option>
                  </select>
                </div>
              </div>
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
              <label class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">Location</span>
                <input
                  type="text"
                  name="event[location]"
                  value={@event_form["location"]}
                  phx-debounce="300"
                  class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                />
              </label>

              <label class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">Repeat</span>
                <select
                  name="event[recurrence]"
                  class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                >
                  <option
                    :for={value <- recurrence_values()}
                    value={value}
                    selected={@event_form["recurrence"] == value}
                  >
                    {recurrence_label(value)}
                  </option>
                </select>
              </label>
            </div>

            <div :if={@event_form["recurrence"] != "none"} class="grid gap-4 sm:grid-cols-2">
              <label class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">Repeat interval</span>
                <input
                  type="number"
                  name="event[recurrence_interval]"
                  value={@event_form["recurrence_interval"]}
                  min="1"
                  step="1"
                  class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                />
              </label>

              <label class="block">
                <span class="mb-1 block text-sm font-medium text-slate-700">Repeat until</span>
                <input
                  type="date"
                  name="event[recurrence_until_date]"
                  value={@event_form["recurrence_until_date"]}
                  class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
                />
              </label>
            </div>

            <div :if={@event_form["recurrence"] == "weekly"}>
              <span class="mb-1 block text-sm font-medium text-slate-700">Weekdays</span>
              <input type="hidden" name="event[recurrence_weekdays][]" value="" />
              <div class="flex flex-wrap gap-2 text-sm text-slate-600">
                <label
                  :for={{label, day} <- weekday_options()}
                  class="flex items-center gap-2 rounded-md border border-slate-200 px-3 py-2"
                >
                  <input
                    type="checkbox"
                    name="event[recurrence_weekdays][]"
                    value={day}
                    checked={weekday_checked?(@event_form, day)}
                  />
                  {label}
                </label>
              </div>
            </div>

            <label class="block">
              <span class="mb-1 block text-sm font-medium text-slate-700">Notes</span>
              <textarea
                name="event[notes]"
                rows="4"
                phx-debounce="300"
                class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
              >{@event_form["notes"]}</textarea>
            </label>

            <button class="inline-flex h-10 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800">
              {if @editing_event_id, do: "Update event", else: "Create event"}
            </button>
          </form>
        </section>

        <section class="rounded-lg border border-slate-200 bg-white shadow-sm">
          <div class="border-b border-slate-200 px-5 py-4">
            <h2 class="font-semibold text-slate-950">Events</h2>
            <p class="text-sm text-slate-500">
              Sorted by the next future occurrence in this calendar's timezone.
            </p>
          </div>

          <ul class="divide-y divide-slate-200">
            <li
              :for={row <- @event_rows}
              class="flex flex-col gap-3 px-5 py-4 lg:flex-row lg:items-start lg:justify-between"
            >
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <span
                    :if={@calendar.color}
                    class="h-2.5 w-2.5 rounded-full"
                    style={"background: #{@calendar.color}"}
                  />
                  <p class="truncate font-medium text-slate-950">{row.event.title}</p>
                  <span
                    :if={row.event.all_day}
                    class="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600"
                  >
                    all day
                  </span>
                </div>
                <p class="mt-1 text-sm text-slate-600">{row.recurrence_summary}</p>
                <p class="mt-1 text-sm text-slate-500">{next_occurrence_text(row.next_occurrence)}</p>
                <p :if={row.event.location} class="mt-1 text-sm text-slate-500">
                  {row.event.location}
                </p>
              </div>

              <div class="flex items-center gap-2">
                <button
                  phx-click="edit_event"
                  phx-value-id={row.event.id}
                  class="rounded-md px-3 py-1.5 text-sm font-medium text-slate-700 transition hover:bg-slate-100"
                >
                  edit
                </button>
                <button
                  phx-click="delete_event"
                  phx-value-id={row.event.id}
                  data-confirm="Delete event?"
                  class="rounded-md px-3 py-1.5 text-sm font-medium text-rose-600 transition hover:bg-rose-50"
                >
                  delete
                </button>
              </div>
            </li>

            <li :if={@event_rows == []} class="px-5 py-10 text-center text-sm text-slate-500">
              No events yet. Create one on the left.
            </li>
          </ul>
        </section>
      </div>
    </div>
    """
  end

  defp load(socket, calendar) do
    socket
    |> assign(:page_title, calendar.name)
    |> assign(:active_nav, :calendars)
    |> assign(:calendar, calendar)
    |> assign(:timezones, Kakemono.TimeZones.list())
    |> assign(:event_rows, Calendars.list_event_rows(calendar.id))
  end

  defp reload(socket) do
    socket |> load(Calendars.get_with_events(socket.assigns.calendar.id))
  end

  defp reset_event_form(socket) do
    socket
    |> assign(:editing_event_id, nil)
    |> assign(:event_form, default_event_form(socket.assigns.calendar.timezone))
  end

  defp default_event_form(timezone) do
    local_now = Calendars.now_utc() |> DateTime.shift_zone!(timezone)

    %{
      "title" => "",
      "all_day" => false,
      "start_on" => local_now |> DateTime.to_date() |> Date.to_iso8601(),
      "start_hour" => "09",
      "start_minute" => "00",
      "end_on" => "",
      "end_hour" => "",
      "end_minute" => "",
      "location" => "",
      "notes" => "",
      "recurrence" => "none",
      "recurrence_interval" => "1",
      "recurrence_weekdays" => [],
      "recurrence_until_date" => ""
    }
  end

  defp event_form_from_event(event, timezone) do
    start_local = DateTime.shift_zone!(event.starts_at_utc, timezone)
    end_local = event.ends_at_utc && DateTime.shift_zone!(event.ends_at_utc, timezone)

    end_on =
      cond do
        is_nil(end_local) ->
          ""

        event.all_day ->
          end_local
          |> DateTime.to_date()
          |> Date.add(-1)
          |> Date.to_iso8601()

        true ->
          end_local |> DateTime.to_date() |> Date.to_iso8601()
      end

    start_time_str = if(event.all_day, do: "", else: Calendar.strftime(start_local, "%H:%M"))

    end_time_str =
      if(event.all_day or is_nil(end_local),
        do: "",
        else: Calendar.strftime(end_local, "%H:%M")
      )

    {start_hour, start_minute} = decompose_time(start_time_str)
    {end_hour, end_minute} = decompose_time(end_time_str)

    %{
      "title" => event.title,
      "all_day" => event.all_day,
      "start_on" => start_local |> DateTime.to_date() |> Date.to_iso8601(),
      "start_hour" => start_hour,
      "start_minute" => start_minute,
      "end_on" => end_on,
      "end_hour" => end_hour,
      "end_minute" => end_minute,
      "location" => event.location || "",
      "notes" => event.notes || "",
      "recurrence" => event.recurrence || "none",
      "recurrence_interval" => to_string(event.recurrence_interval || 1),
      "recurrence_weekdays" =>
        Enum.map(Kakemono.Calendars.Event.recurrence_weekdays(event), &Integer.to_string/1),
      "recurrence_until_date" =>
        if(event.recurrence_until_date,
          do: Date.to_iso8601(event.recurrence_until_date),
          else: ""
        )
    }
  end

  defp recurrence_values, do: Kakemono.Calendars.Event.recurrence_values()
  defp recurrence_label("none"), do: "Once"
  defp recurrence_label("daily"), do: "Daily"
  defp recurrence_label("weekly"), do: "Weekly"
  defp recurrence_label("monthly"), do: "Monthly"
  defp recurrence_label("yearly"), do: "Yearly"

  defp weekday_options do
    [{"Mon", 1}, {"Tue", 2}, {"Wed", 3}, {"Thu", 4}, {"Fri", 5}, {"Sat", 6}, {"Sun", 7}]
  end

  defp weekday_checked?(event_form, day) do
    Integer.to_string(day) in List.wrap(event_form["recurrence_weekdays"])
  end

  defp next_occurrence_text(nil), do: "No future occurrence scheduled"

  defp next_occurrence_text(occurrence) do
    if occurrence.all_day do
      "Next: " <> Calendar.strftime(occurrence.local_start, "%a, %b %-d") <> " • all day"
    else
      "Next: " <> Calendar.strftime(occurrence.local_start, "%a, %b %-d %H:%M")
    end
  end

  defp compose_time_params(params) do
    params
    |> Map.put("start_time", compose_time(params["start_hour"], params["start_minute"]))
    |> Map.put("end_time", compose_time(params["end_hour"], params["end_minute"]))
  end

  defp decompose_time(""), do: {"", ""}
  defp decompose_time(nil), do: {"", ""}

  defp decompose_time(time_str) do
    case String.split(time_str, ":") do
      [h, m] ->
        minute = String.to_integer(m)
        rounded = div(minute + 2, 5) * 5
        rounded = if rounded >= 60, do: 55, else: rounded
        {h, String.pad_leading(Integer.to_string(rounded), 2, "0")}

      _ ->
        {"", ""}
    end
  end

  defp compose_time(nil, _), do: ""
  defp compose_time(_, nil), do: ""
  defp compose_time("", _), do: ""
  defp compose_time(_, ""), do: ""

  defp compose_time(hour, minute) do
    String.pad_leading(hour, 2, "0") <> ":" <> String.pad_leading(minute, 2, "0")
  end

  defp derive_form_state(form, previous) do
    form
    |> apply_all_day_rules(previous)
    |> apply_recurrence_rules()
    |> apply_end_time_default(previous)
  end

  defp apply_all_day_rules(form, previous) do
    all_day = truthy?(form["all_day"])
    was_all_day = truthy?(previous["all_day"])

    cond do
      all_day ->
        form
        |> Map.put("start_hour", "")
        |> Map.put("start_minute", "")
        |> Map.put("end_on", "")
        |> Map.put("end_hour", "")
        |> Map.put("end_minute", "")

      was_all_day and not all_day ->
        form
        |> Map.put("start_hour", "09")
        |> Map.put("start_minute", "00")
        |> Map.put("end_hour", "10")
        |> Map.put("end_minute", "00")

      true ->
        form
    end
  end

  defp apply_recurrence_rules(form) do
    if form["recurrence"] == "none" do
      form
      |> Map.put("recurrence_interval", "1")
      |> Map.put("recurrence_until_date", "")
      |> Map.put("recurrence_weekdays", [])
    else
      form
    end
  end

  defp apply_end_time_default(form, previous) do
    start_hour = form["start_hour"]
    prev_start_hour = previous["start_hour"]

    if start_hour != "" and start_hour != prev_start_hour and
         (form["end_hour"] == "" or auto_filled_end?(previous)) do
      case Integer.parse(start_hour) do
        {h, ""} when h < 23 ->
          form
          |> Map.put("end_hour", String.pad_leading(Integer.to_string(h + 1), 2, "0"))
          |> Map.put("end_minute", form["start_minute"])

        _ ->
          form
      end
    else
      form
    end
  end

  defp auto_filled_end?(form) do
    with {sh, ""} <- Integer.parse(form["start_hour"] || ""),
         {eh, ""} <- Integer.parse(form["end_hour"] || "") do
      eh == sh + 1 and form["start_minute"] == form["end_minute"]
    else
      _ -> false
    end
  end

  defp hour_options do
    for h <- 0..23, do: String.pad_leading(Integer.to_string(h), 2, "0")
  end

  defp minute_options do
    for m <- 0..55//5, do: String.pad_leading(Integer.to_string(m), 2, "0")
  end

  defp truthy?(value) when value in [true, "true", "on", 1, "1"], do: true
  defp truthy?(_), do: false

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
