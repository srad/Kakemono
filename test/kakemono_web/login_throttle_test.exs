defmodule KakemonoWeb.LoginThrottleTest do
  use ExUnit.Case, async: false

  alias KakemonoWeb.LoginThrottle

  setup do
    LoginThrottle.reset()
    on_exit(&LoginThrottle.reset/0)
    :ok
  end

  test "allows attempts until the failure limit is reached" do
    assert :ok = LoginThrottle.check()

    for _ <- 1..10, do: LoginThrottle.record_failure()

    assert {:error, :rate_limited} = LoginThrottle.check()
  end

  test "reset clears the failure counter" do
    for _ <- 1..10, do: LoginThrottle.record_failure()
    assert {:error, :rate_limited} = LoginThrottle.check()

    LoginThrottle.reset()
    assert :ok = LoginThrottle.check()
  end
end
