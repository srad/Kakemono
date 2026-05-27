defmodule KakemonoWeb.FrontendTest do
  @moduledoc """
  Runs the Vitest frontend suite (`npm test` in assets/) as part of `mix test`,
  so JS hook regressions (e.g. `this.flashStatus is not a function`) fail CI
  without anyone having to remember to run a second command.

  Skipped automatically when `npm` is unavailable.
  """
  use ExUnit.Case, async: false

  @assets_dir Path.expand("../../assets", __DIR__)

  @tag :frontend
  test "vitest suite passes" do
    case System.find_executable("npm") do
      nil ->
        IO.warn("npm not found in PATH — skipping frontend test suite")

      npm ->
        {out, status} =
          System.cmd(npm, ["test", "--silent"], cd: @assets_dir, stderr_to_stdout: true)

        assert status == 0, """
        Vitest suite failed (exit #{status}):

        #{out}
        """
    end
  end
end
