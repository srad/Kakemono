defmodule Kakemono.Repo.Migrations.CreatePhase1Tables do
  use Ecto.Migration

  def change do
    create table(:playlists) do
      add :name, :string, null: false
      add :fit_mode, :string, null: false, default: "contain"
      add :transition_duration_ms, :integer
      timestamps()
    end

    create table(:widget_instances) do
      add :widget_type, :string, null: false
      add :config, :map, null: false, default: %{}
      timestamps()
    end

    create index(:widget_instances, [:widget_type])

    create table(:scenes) do
      add :name, :string, null: false
      add :mode, :string, null: false, default: "dashboard"
      add :layout, :map, null: false, default: %{"cells" => []}
      add :schedule, :map
      timestamps()
    end

    create table(:displays, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :current_scene_id, references(:scenes, on_delete: :nilify_all)
      add :last_heartbeat_at, :utc_datetime
      timestamps()
    end

    create table(:media_items) do
      add :filename, :string, null: false
      add :original_filename, :string, null: false
      add :mime_type, :string, null: false
      add :width, :integer
      add :height, :integer
      add :duration_ms, :integer
      add :thumbnail_path, :string
      add :status, :string, null: false, default: "pending"
      timestamps()
    end

    create index(:media_items, [:status])

    create table(:playlist_entries) do
      add :playlist_id, references(:playlists, on_delete: :delete_all), null: false
      add :media_item_id, references(:media_items, on_delete: :delete_all), null: false
      add :order_index, :integer, null: false
      timestamps()
    end

    create unique_index(:playlist_entries, [:playlist_id, :order_index])
    create index(:playlist_entries, [:playlist_id])
  end
end
