defmodule Kakemono.Backup do
  @moduledoc false

  def backups_dir do
    Kakemono.DataDir.backups_dir()
  end

  def list do
    dir = backups_dir()
    File.mkdir_p!(dir)

    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".zip"))
    |> Enum.map(fn filename ->
      path = Path.join(dir, filename)
      %File.Stat{size: size, mtime: mtime} = File.stat!(path, time: :posix)
      %{filename: filename, path: path, size: size, created_at: DateTime.from_unix!(mtime)}
    end)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  end

  def create do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    dir = backups_dir()
    File.mkdir_p!(dir)
    out = Path.join(dir, "kakemono-#{timestamp}.zip")

    entries = collect_entries(db_path(), uploads_dir())

    if entries == [] do
      {:error, "DB file not found at #{db_path()}"}
    else
      case :zip.create(String.to_charlist(out), entries) do
        {:ok, _} -> {:ok, Path.basename(out)}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  def delete(filename) do
    case safe_path(filename) do
      nil ->
        {:error, :invalid_filename}

      path ->
        if File.exists?(path) do
          File.rm!(path)
          :ok
        else
          {:error, :not_found}
        end
    end
  end

  def path_for(filename), do: safe_path(filename)

  defp safe_path(filename) do
    if Regex.match?(~r/\Akakemono-\d{8}-\d{6}\.zip\z/, filename) do
      Path.join(backups_dir(), filename)
    end
  end

  defp db_path do
    cond do
      path = System.get_env("DATABASE_PATH") -> path
      cfg = Application.get_env(:kakemono, Kakemono.Repo) -> cfg[:database] |> Path.expand()
      true -> Kakemono.DataDir.path("kakemono.db")
    end
  end

  defp uploads_dir do
    Kakemono.DataDir.uploads_dir()
  end

  defp collect_entries(db_path, uploads_dir) do
    db_entries =
      [db_path, db_path <> "-wal", db_path <> "-shm"]
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(&to_zip_entry/1)

    upload_entries =
      if File.dir?(uploads_dir) do
        uploads_dir
        |> File.ls!()
        |> Enum.flat_map(fn name ->
          path = Path.join(uploads_dir, name)
          if File.regular?(path), do: [to_zip_entry(path)], else: []
        end)
      else
        []
      end

    db_entries ++ upload_entries
  end

  defp to_zip_entry(path) do
    {String.to_charlist(Path.basename(path)), File.read!(path)}
  end
end
