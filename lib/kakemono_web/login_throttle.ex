defmodule KakemonoWeb.LoginThrottle do
  @moduledoc """
  Minimal global throttle for backend login attempts.

  The backend is a single shared password and the app sits behind a reverse
  proxy (so `remote_ip` collapses to the proxy), therefore one global counter is
  used rather than a per-IP key. After `@max_failures` failed attempts within a
  rolling `@window_ms` window, `check/0` reports `{:error, :rate_limited}` until
  the window elapses or a successful login calls `reset/0`.
  """
  use GenServer

  @max_failures 10
  @window_ms 60_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Whether another login attempt is currently allowed."
  def check, do: GenServer.call(__MODULE__, :check)

  @doc "Record a failed login attempt."
  def record_failure, do: GenServer.call(__MODULE__, :record_failure)

  @doc "Clear the failure counter (call on a successful login)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_), do: {:ok, %{count: 0, window_start: now()}}

  @impl true
  def handle_call(:check, _from, state) do
    state = expire(state)

    if state.count >= @max_failures do
      {:reply, {:error, :rate_limited}, state}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:record_failure, _from, state) do
    state = expire(state)
    {:reply, :ok, %{state | count: state.count + 1}}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{count: 0, window_start: now()}}
  end

  # Reset the counter once the rolling window has elapsed.
  defp expire(state) do
    if now() - state.window_start > @window_ms do
      %{count: 0, window_start: now()}
    else
      state
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
