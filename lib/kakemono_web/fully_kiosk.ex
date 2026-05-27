defmodule KakemonoWeb.FullyKiosk do
  @moduledoc """
  Helpers for remote-controlling Fully Kiosk Browser on connected displays.

  Commands travel over the existing LiveView WebSocket via PubSub:
    control panel → PubSub → DisplayLive → push_event → window.fully.<cmd>()

  Supported commands (must be valid Fully Kiosk JS API method names):
    "screenOn"    — turn the screen on / wake from screensaver
    "screenOff"   — turn the screen off / start screensaver
    "restartApp"  — restart Fully Kiosk (reloads the page)
    "reloadPage"  — reload the current URL without restarting the app

  The display must be running Fully Kiosk Browser for these to have effect;
  on a regular browser the JS calls are silently ignored (window.fully is undefined).
  """

  @valid_commands ~w(screenOn screenOff restartApp reloadPage)

  @doc "Returns the list of commands the UI may offer."
  def commands, do: @valid_commands

  @doc "Broadcast a Fully Kiosk command to a specific display's LiveView process."
  def broadcast(display_id, cmd) when cmd in @valid_commands do
    Phoenix.PubSub.broadcast(Kakemono.PubSub, "display:#{display_id}", {:fully_kiosk_cmd, cmd})
  end
end
