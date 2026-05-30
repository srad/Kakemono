defmodule Kakemono.CalendarsTest do
  use Kakemono.DataCase, async: false

  alias Kakemono.{Calendars, Fixtures}

  setup do
    on_exit(fn -> Application.delete_env(:kakemono, :calendar_now_fn) end)
    :ok
  end

  test "creates calendars and validates timezones" do
    assert {:ok, calendar} =
             Calendars.create_calendar(%{
               name: "Family",
               timezone: "Europe/Berlin",
               color: "#123456"
             })

    assert calendar.timezone == "Europe/Berlin"

    assert {:error, changeset} =
             Calendars.create_calendar(%{name: "Broken", timezone: "Mars/Olympus"})

    assert "is invalid" in errors_on(changeset).timezone
  end

  test "yearly all-day events repeat for birthdays" do
    calendar = Fixtures.calendar_fixture()

    assert {:ok, _event} =
             Calendars.create_event(calendar, %{
               title: "Alice birthday",
               all_day: "true",
               start_on: "2024-05-30",
               recurrence: "yearly",
               recurrence_interval: "1"
             })

    occurrences =
      Calendars.list_occurrences(
        calendar.id,
        ~U[2026-05-01 00:00:00Z],
        ~U[2026-06-15 00:00:00Z]
      )

    assert [%{title: "Alice birthday", all_day: true, local_start: local_start}] = occurrences
    assert DateTime.to_date(local_start) == ~D[2026-05-30]
  end

  test "weekly recurrence expands explicit weekdays" do
    calendar = Fixtures.calendar_fixture()

    assert {:ok, _event} =
             Calendars.create_event(calendar, %{
               title: "Open hours",
               start_on: "2026-05-04",
               start_time: "08:00",
               end_on: "2026-05-04",
               end_time: "12:00",
               recurrence: "weekly",
               recurrence_interval: "1",
               recurrence_weekdays: ["1", "3", "5"]
             })

    occurrences =
      Calendars.list_occurrences(
        calendar.id,
        ~U[2026-05-04 00:00:00Z],
        ~U[2026-05-11 00:00:00Z]
      )

    assert Enum.map(occurrences, &DateTime.to_date(&1.local_start)) == [
             ~D[2026-05-04],
             ~D[2026-05-06],
             ~D[2026-05-08]
           ]
  end

  test "calendar timezone keeps recurring local wall clock time across DST" do
    calendar = Fixtures.calendar_fixture(%{timezone: "Europe/Berlin"})

    assert {:ok, _event} =
             Calendars.create_event(calendar, %{
               title: "Morning standup",
               start_on: "2026-03-28",
               start_time: "09:00",
               end_on: "2026-03-28",
               end_time: "10:00",
               recurrence: "daily",
               recurrence_interval: "1"
             })

    occurrences =
      Calendars.list_occurrences(
        calendar.id,
        ~U[2026-03-28 00:00:00Z],
        ~U[2026-03-31 00:00:00Z]
      )

    assert Enum.map(occurrences, & &1.local_start.hour) == [9, 9, 9]
    assert Enum.map(occurrences, & &1.start_at.hour) == [8, 7, 7]
  end

  test "two week widget view aligns to Monday and spans two calendar weeks" do
    calendar = Fixtures.calendar_fixture()

    Fixtures.calendar_event_fixture(calendar, %{
      title: "Market",
      start_on: "2026-05-28",
      start_time: "11:00",
      end_on: "2026-05-28",
      end_time: "12:00"
    })

    view = Calendars.widget_view(calendar.id, "two_week", ~U[2026-05-28 08:00:00Z])
    first_day = view.weeks |> List.first() |> List.first()
    last_day = view.weeks |> List.last() |> List.last()

    assert view.view_mode == "two_week"
    assert length(view.weeks) == 2
    assert first_day.date == ~D[2026-05-25]
    assert last_day.date == ~D[2026-06-07]
    assert view.today == ~D[2026-05-28]

    market_day =
      view.weeks
      |> List.flatten()
      |> Enum.find(&(&1.date == ~D[2026-05-28]))

    assert market_day.event_count == 1
    assert [%{title: "Market"}] = market_day.visible_occurrences
  end

  test "month widget view pads the leading days to a full Monday-first grid" do
    calendar = Fixtures.calendar_fixture()
    view = Calendars.widget_view(calendar.id, "month", ~U[2026-05-15 12:00:00Z])
    first_week = List.first(view.weeks)

    assert view.view_mode == "month"
    assert length(first_week) == 7
    assert Date.day_of_week(hd(first_week).date) == 1
    assert Enum.any?(first_week, &(!&1.in_range))
    assert Enum.any?(List.flatten(view.weeks), &(&1.date == ~D[2026-05-31] and &1.in_range))
  end

  test "grid widget view duplicates multi-day events per day and tracks overflow" do
    calendar = Fixtures.calendar_fixture()

    Fixtures.calendar_event_fixture(calendar, %{
      title: "Conference",
      start_on: "2026-05-30",
      start_time: "09:00",
      end_on: "2026-06-01",
      end_time: "10:00"
    })

    Fixtures.calendar_event_fixture(calendar, %{
      title: "Breakfast",
      start_on: "2026-05-30",
      start_time: "08:00",
      end_on: "2026-05-30",
      end_time: "08:30"
    })

    Fixtures.calendar_event_fixture(calendar, %{
      title: "Lunch",
      start_on: "2026-05-30",
      start_time: "12:00",
      end_on: "2026-05-30",
      end_time: "13:00"
    })

    Fixtures.calendar_event_fixture(calendar, %{
      title: "Dinner",
      start_on: "2026-05-30",
      start_time: "18:00",
      end_on: "2026-05-30",
      end_time: "19:00"
    })

    view = Calendars.widget_view(calendar.id, "two_week", ~U[2026-05-28 10:00:00Z])

    days =
      view.weeks
      |> List.flatten()
      |> Map.new(&{&1.date, &1})

    assert days[~D[2026-05-30]].event_count == 4
    assert length(days[~D[2026-05-30]].visible_occurrences) == 2
    assert days[~D[2026-05-30]].overflow_count == 2

    assert Enum.any?(days[~D[2026-05-31]].visible_occurrences, &(&1.title == "Conference"))
    assert Enum.any?(days[~D[2026-06-01]].visible_occurrences, &(&1.title == "Conference"))
  end
end
