defmodule KakemonoWeb.CalendarsLiveTest do
  use KakemonoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Kakemono.{Calendars, Fixtures}

  test "lists and creates calendars", %{conn: conn} do
    {:ok, view, html} = live(conn, "/c/calendars")
    assert html =~ "No calendars yet"

    view
    |> form("#create-calendar-form", %{
      "calendar" => %{
        "name" => "Family",
        "timezone" => "Europe/Berlin",
        "color" => "#ff0000"
      }
    })
    |> render_submit()

    assert render(view) =~ "Family"

    assert [%{name: "Family", timezone: "Europe/Berlin", color: "#ff0000"}] =
             Calendars.list_calendars()
  end

  test "edits a calendar and manages events", %{conn: conn} do
    calendar = Fixtures.calendar_fixture(%{name: "Family", timezone: "Europe/Berlin"})
    {:ok, view, html} = live(conn, "/c/calendars/#{calendar.id}")

    assert html =~ "Calendar settings"

    view
    |> form("#calendar-settings-form", %{
      "calendar" => %{
        "name" => "Family HQ",
        "timezone" => "Etc/UTC",
        "color" => "#00ff00"
      }
    })
    |> render_submit()

    assert Calendars.get!(calendar.id).name == "Family HQ"

    view
    |> element("#event-form")
    |> render_change(%{"event" => %{"all_day" => "true", "recurrence" => "yearly"}})

    view
    |> form("#event-form", %{
      "event" => %{
        "title" => "Birthday",
        "start_on" => "2026-05-30",
        "location" => "Home",
        "notes" => "Cake",
        "recurrence_interval" => "1",
        "recurrence_until_date" => ""
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Birthday"
    assert html =~ "Yearly"
    assert html =~ "Home"

    [event] = Calendars.list_events(calendar.id)

    render_click(view, "edit_event", %{"id" => event.id})

    view
    |> form("#event-form", %{
      "event" => %{
        "title" => "Birthday dinner",
        "start_on" => "2026-05-30",
        "location" => "Home",
        "notes" => "Guests",
        "recurrence_interval" => "1",
        "recurrence_until_date" => ""
      }
    })
    |> render_submit()

    assert render(view) =~ "Birthday dinner"
  end

  test "creates a timed event with hour/minute selects", %{conn: conn} do
    calendar = Fixtures.calendar_fixture(%{name: "Work", timezone: "Europe/Berlin"})
    {:ok, view, _html} = live(conn, "/c/calendars/#{calendar.id}")

    view
    |> form("#event-form", %{
      "event" => %{
        "title" => "Meeting",
        "start_on" => "2026-06-01",
        "start_hour" => "14",
        "start_minute" => "30",
        "end_on" => "2026-06-01",
        "end_hour" => "15",
        "end_minute" => "30",
        "location" => "Office",
        "notes" => ""
      }
    })
    |> render_submit()

    assert render(view) =~ "Meeting"
    [event] = Calendars.list_events(calendar.id)
    refute event.all_day
  end
end
