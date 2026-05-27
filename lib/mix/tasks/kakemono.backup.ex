defmodule Mix.Tasks.Kakemono.Backup do
  @moduledoc """
  Creates a timestamped zip archive containing the SQLite database
  (plus -wal/-shm sidecar files if present) and the uploads directory.

      mix kakemono.backup

  The archive is written to `<data-dir>/backups/kakemono-YYYYMMDD-HHMMSS.zip`
  by default.

  Honours `KAKEMONO_DATA_DIR`, `DATABASE_PATH`, `KAKEMONO_UPLOADS_DIR`, and
  `KAKEMONO_BACKUPS_DIR` env vars.
  """
  use Mix.Task

  @shortdoc "Zip SQLite database and uploads"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    case Kakemono.Backup.create() do
      {:ok, filename} ->
        Mix.shell().info(
          "Backup written to #{Path.join(Kakemono.Backup.backups_dir(), filename)}"
        )

      {:error, reason} ->
        Mix.shell().error("Backup failed: #{reason}")
    end
  end
end
