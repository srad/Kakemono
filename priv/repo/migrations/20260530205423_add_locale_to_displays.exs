defmodule Kakemono.Repo.Migrations.AddLocaleToDisplays do
  use Ecto.Migration

  def change do
    alter table(:displays) do
      add :locale, :string, default: "en", null: false
    end
  end
end
