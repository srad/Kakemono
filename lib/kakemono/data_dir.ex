defmodule Kakemono.DataDir do
  @moduledoc false

  def dir do
    :kakemono
    |> Application.get_env(:data_dir, "data")
    |> Path.expand()
  end

  def path(parts), do: Path.join(dir(), List.wrap(parts))

  def uploads_dir, do: configured_path(:uploads_dir, "uploads")

  def backups_dir, do: configured_path(:backups_dir, "backups")

  def secret_file do
    case Application.get_env(:kakemono, :api_secret_file, :default) do
      nil -> nil
      :default -> path("secret.key")
      configured -> Path.expand(configured)
    end
  end

  defp configured_path(key, fallback) do
    :kakemono
    |> Application.get_env(key)
    |> configured_or(path(fallback))
    |> Path.expand()
  end

  defp configured_or(nil, fallback), do: fallback
  defp configured_or(configured, _fallback), do: configured
end
