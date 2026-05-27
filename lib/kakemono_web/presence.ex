defmodule KakemonoWeb.Presence do
  use Phoenix.Presence,
    otp_app: :kakemono,
    pubsub_server: Kakemono.PubSub

  @topic "presence:displays"

  def topic, do: @topic

  def track_display(pid, display_id) do
    track(pid, @topic, display_id, %{online_at: System.system_time(:second)})
  end

  def online_display_ids do
    @topic |> list() |> Map.keys()
  end
end
