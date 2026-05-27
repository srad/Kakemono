defmodule Mix.Tasks.Kakemono.Purge do
  @moduledoc """
  Drops the database, recreates it, runs migrations, and deletes every
  uploaded file under `Kakemono.Media.uploads_dir()` (including the
  `thumbs/` subdirectory).

  Pre-release helper — there is no production data to protect yet.

      mix kakemono.purge          # asks for confirmation
      mix kakemono.purge --yes    # skip confirmation (for scripts / CI)

  Honours `MIX_ENV`; defaults to `:dev` if unset.
  """
  use Mix.Task

  @shortdoc "Drop DB, recreate, migrate, and wipe uploads"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [yes: :boolean], aliases: [y: :yes])

    env = Mix.env()
    uploads = uploads_dir()

    Mix.shell().info("""

    About to PURGE all Kakemono data:
      * MIX_ENV   = #{env}
      * database  = drop + create + migrate
      * uploads   = delete everything in #{uploads}
    """)

    unless opts[:yes] || confirm?() do
      Mix.shell().info("Aborted.")
      exit(:normal)
    end

    Mix.Task.run("ecto.drop", ["--quiet"])
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])

    wipe_uploads(uploads)

    Mix.shell().info("Done.")
  end

  defp confirm? do
    case Mix.shell().prompt("Type 'yes' to continue:") |> String.trim() |> String.downcase() do
      "yes" -> true
      _ -> false
    end
  end

  defp uploads_dir do
    Application.load(:kakemono)

    Kakemono.DataDir.uploads_dir()
  end

  defp wipe_uploads(dir) do
    if File.dir?(dir) do
      for entry <- File.ls!(dir) do
        path = Path.join(dir, entry)
        File.rm_rf!(path)
      end

      Mix.shell().info("Wiped uploads in #{dir}")
    else
      File.mkdir_p!(dir)
      Mix.shell().info("Uploads dir #{dir} did not exist; created.")
    end
  end
end
