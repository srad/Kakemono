defmodule Kakemono.Repo.Migrations.AddCalendars do
  use Ecto.Migration

  def change do
    create table(:calendars) do
      add :name, :string, null: false
      add :timezone, :string, null: false, default: "Etc/UTC"
      add :color, :string
      timestamps()
    end

    create table(:calendar_events) do
      add :calendar_id, references(:calendars, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :starts_at_utc, :utc_datetime, null: false
      add :ends_at_utc, :utc_datetime
      add :all_day, :boolean, null: false, default: false
      add :location, :string
      add :notes, :text
      add :recurrence, :string, null: false, default: "none"
      add :recurrence_interval, :integer, null: false, default: 1
      add :recurrence_weekdays, :string, null: false, default: ""
      add :recurrence_until_date, :date
      timestamps()
    end

    create index(:calendar_events, [:calendar_id])
    create index(:calendar_events, [:starts_at_utc])
  end
end
