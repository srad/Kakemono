defmodule Kakemono.Repo.Migrations.AddSceneIdToWidgetInstances do
  use Ecto.Migration

  def change do
    alter table(:widget_instances) do
      add :scene_id, references(:scenes, on_delete: :delete_all), null: false
    end

    create index(:widget_instances, [:scene_id])
  end
end
