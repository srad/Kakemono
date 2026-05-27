defmodule Kakemono.Repo.Migrations.AddAspectRatioToScenes do
  use Ecto.Migration

  def change do
    alter table(:scenes) do
      add :aspect_ratio, :string, null: false, default: "16:9"
    end
  end
end
