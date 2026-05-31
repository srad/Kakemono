defmodule KakemonoWeb.LocaleHook do
  @moduledoc false

  def on_mount(:backend, _params, _session, socket) do
    Gettext.put_locale(KakemonoWeb.Gettext, Kakemono.Locale.get())
    {:cont, socket}
  end

  def on_mount(:display, _params, _session, socket) do
    {:cont, socket}
  end
end
