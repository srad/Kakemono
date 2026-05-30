defmodule Kakemono.Fixtures do
  @moduledoc "Shared test fixtures for Phase 1."
  alias Kakemono.{Calendars, Displays, Playlists, Repo}
  alias Kakemono.Media.Item

  def display!(id, name \\ nil) do
    display_fixture(%{id: id, name: name || "Display #{id}"})
  end

  def display_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{id: "tablet-#{System.unique_integer([:positive])}", name: "Test"},
        Map.new(attrs)
      )

    {:ok, d} = Displays.create(attrs)
    d
  end

  @doc "Insert a media item directly (skipping upload/transcode)."
  def media_item_fixture(attrs \\ %{}) do
    base = %{
      filename: "#{Ecto.UUID.generate()}.jpg",
      original_filename: "test.jpg",
      mime_type: "image/jpeg",
      status: "ready"
    }

    {:ok, i} = %Item{} |> Item.changeset(Map.merge(base, Map.new(attrs))) |> Repo.insert()
    i
  end

  def playlist_fixture(attrs \\ %{}) do
    {:ok, p} =
      Playlists.create(
        Map.merge(%{name: "PL #{System.unique_integer([:positive])}"}, Map.new(attrs))
      )

    p
  end

  @doc """
  Write a small valid JPEG to a tmp file and return its path.
  Uses ffmpeg (always present in the dev image) so the output is guaranteed
  readable by libvips for downstream Image.* calls in the TranscodeWorker.
  """
  def write_test_jpeg do
    path = Path.join(System.tmp_dir!(), "kakemono_test_#{System.unique_integer([:positive])}.jpg")

    {_, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-y",
          "-f",
          "lavfi",
          "-i",
          "color=c=red:s=128x128:d=1",
          "-frames:v",
          "1",
          path
        ],
        stderr_to_stdout: true
      )

    path
  end

  def widget_instance_fixture(attrs \\ %{}) do
    type = attrs[:type] || attrs[:widget_type] || "clock"
    config = attrs[:config] || %{}
    scene_id = attrs[:scene_id] || scene_fixture().id
    {:ok, inst} = Kakemono.Widgets.create_instance(type, scene_id, config)
    inst
  end

  def calendar_fixture(attrs \\ %{}) do
    {:ok, calendar} =
      Calendars.create_calendar(
        Map.merge(
          %{
            name: "Calendar #{System.unique_integer([:positive])}",
            timezone: "Etc/UTC",
            color: "#38bdf8"
          },
          Map.new(attrs)
        )
      )

    calendar
  end

  def calendar_event_fixture(calendar, attrs \\ %{}) do
    defaults = %{
      title: "Event #{System.unique_integer([:positive])}",
      start_on: "2026-05-30",
      start_time: "09:00",
      end_on: "2026-05-30",
      end_time: "10:00",
      recurrence: "none",
      recurrence_interval: "1"
    }

    {:ok, event} = Calendars.create_event(calendar, Map.merge(defaults, Map.new(attrs)))
    event
  end

  def scene_fixture(attrs \\ %{}) do
    base = %{
      name: "Scene #{System.unique_integer([:positive])}",
      mode: "dashboard",
      layout: %{"cells" => []}
    }

    {:ok, p} = Kakemono.Scenes.create(Map.merge(base, Map.new(attrs)))
    p
  end
end
