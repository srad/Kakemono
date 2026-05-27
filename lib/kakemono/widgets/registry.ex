defmodule Kakemono.Widgets.Registry do
  @moduledoc """
  Compile-time list of widget modules. Adding a new widget is two edits:
  implement `Kakemono.Widget` in a new module, then append it here.
  """

  alias Kakemono.Widgets.{Clock, Instagram, Rss, Slideshow, Weather}

  @widgets [Clock, Instagram, Rss, Slideshow, Weather]

  def all, do: @widgets

  def types, do: Enum.map(@widgets, & &1.type())

  @doc "Return the widget module for a given type string, or nil."
  def fetch(type) when is_binary(type) do
    Enum.find(@widgets, fn mod -> mod.type() == type end)
  end
end
