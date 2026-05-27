defmodule Kakemono.Repo.Migrations.AddOrientationAndColorSchemeToScenes do
  use Ecto.Migration

  def change do
    alter table(:scenes) do
      add :orientation, :string, null: false, default: "portrait"
      add :color_scheme, :string, null: false, default: "light"
    end
  end
end
