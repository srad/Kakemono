defmodule KakemonoWeb.CalendarsLive.Index do
  use KakemonoWeb, :live_view

  alias Kakemono.Calendars

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Kakemono.PubSub, "calendars")

    {:ok,
     socket
     |> assign(:page_title, gettext("Calendars"))
     |> assign(:active_nav, :calendars)
     |> assign(:timezones, Kakemono.TimeZones.list())
     |> load()}
  end

  @impl true
  def handle_event("create", %{"calendar" => params}, socket) do
    case Calendars.create_calendar(params) do
      {:ok, calendar} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, gettext("Created %{name}", name: calendar.name))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    calendar = Calendars.get!(id)
    {:ok, _} = Calendars.delete_calendar(calendar)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({:calendar_list_updated, _}, socket) do
    {:noreply, load(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p class="text-sm font-medium text-slate-500">{gettext("Scheduling")}</p>
          <h1 class="text-2xl font-semibold tracking-tight text-slate-950">{gettext("Calendars")}</h1>
        </div>
        <p class="text-sm text-slate-500">{ngettext("1 calendar", "%{count} calendars", length(@calendars))}</p>
      </div>

      <form
        id="create-calendar-form"
        phx-submit="create"
        class="grid gap-3 rounded-lg border border-slate-200 bg-white p-5 shadow-sm lg:grid-cols-[minmax(0,1fr)_16rem_10rem_auto]"
      >
        <input
          name="calendar[name]"
          placeholder={gettext("New calendar name")}
          class="rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
        />
        <select
          name="calendar[timezone]"
          class="rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
        >
          <option :for={timezone <- @timezones} value={timezone} selected={timezone == "Etc/UTC"}>
            {timezone}
          </option>
        </select>
        <input
          type="color"
          name="calendar[color]"
          value="#38bdf8"
          class="h-10 w-full rounded-md border border-slate-300 bg-white p-1"
        />
        <button class="inline-flex h-10 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800">
          {gettext("Create")}
        </button>
      </form>

      <ul class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
        <li
          :for={calendar <- @calendars}
          class="flex items-center justify-between gap-3 border-b border-slate-200 px-5 py-4 last:border-b-0"
        >
          <div class="min-w-0">
            <.link
              navigate={~p"/c/calendars/#{calendar.id}"}
              class="truncate font-medium text-slate-950 hover:text-slate-700"
            >
              {calendar.name}
            </.link>
            <p class="text-sm text-slate-500">{calendar.timezone}</p>
          </div>
          <div class="flex items-center gap-3">
            <span
              :if={calendar.color}
              class="h-4 w-4 rounded-full border border-slate-200"
              style={"background: #{calendar.color}"}
            />
            <button
              phx-click="delete"
              phx-value-id={calendar.id}
              data-confirm={gettext("Delete calendar?")}
              class="rounded-md px-2.5 py-1.5 text-sm font-medium text-rose-600 transition hover:bg-rose-50"
            >
              {gettext("delete")}
            </button>
          </div>
        </li>
      </ul>

      <p
        :if={@calendars == []}
        class="rounded-lg border border-dashed border-slate-300 bg-white px-5 py-10 text-center text-sm text-slate-500"
      >
        {gettext("No calendars yet. Create one above.")}
      </p>
    </div>
    """
  end

  defp load(socket) do
    assign(socket, :calendars, Calendars.list_calendars())
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
