defmodule Kakemono.Widgets.Registry do
  @moduledoc """
  Discovers widget modules at runtime — any module that `use Kakemono.Widget`
  (and therefore exports the `__widget__/0` marker) is a widget. Adding a widget
  is just creating the module; there is no list to maintain here.
  """

  @doc "All widget modules, sorted by display name."
  def all do
    {:ok, mods} = :application.get_key(:kakemono, :modules)

    mods
    |> Enum.filter(&widget?/1)
    |> Enum.sort_by(& &1.name())
  end

  @doc "The widget module for a given type string, or nil."
  def fetch(type) when is_binary(type) do
    Enum.find(all(), fn mod -> mod.type() == type end)
  end

  @doc "All widget type strings."
  def types, do: Enum.map(all(), & &1.type())

  defp widget?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :__widget__, 0)
  end
end
