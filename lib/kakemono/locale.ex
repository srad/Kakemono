defmodule Kakemono.Locale do
  @moduledoc false

  @supported ~w(en de)
  @default "en"

  def supported, do: @supported
  def default, do: @default

  def get do
    Application.get_env(:kakemono, :backend_locale) || read_persisted() || @default
  end

  def set(locale) when locale in @supported do
    Application.put_env(:kakemono, :backend_locale, locale)
    path = Kakemono.DataDir.locale_file()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, locale)
    :ok
  end

  def valid?(locale), do: locale in @supported

  defp read_persisted do
    path = Kakemono.DataDir.locale_file()

    case File.read(path) do
      {:ok, content} ->
        locale = String.trim(content)
        if locale in @supported, do: locale

      _ ->
        nil
    end
  end
end
