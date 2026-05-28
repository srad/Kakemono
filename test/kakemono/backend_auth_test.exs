defmodule Kakemono.BackendAuthTest do
  use ExUnit.Case, async: false
  import Bitwise

  alias Kakemono.BackendAuth

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "kakemono_backend_pw_#{System.unique_integer([:positive])}.hash"
      )

    prev = Application.get_env(:kakemono, :backend_password_file, :default)
    Application.put_env(:kakemono, :backend_password_file, path)

    on_exit(fn ->
      File.rm_rf(path)
      Application.put_env(:kakemono, :backend_password_file, prev)
    end)

    %{path: path}
  end

  test "configured? is false until a password is set" do
    refute BackendAuth.configured?()
    assert :ok = BackendAuth.set_password("hunter2-long-enough")
    assert BackendAuth.configured?()
  end

  test "set_password rejects passwords below the minimum length" do
    assert {:error, :too_short} = BackendAuth.set_password("short")
    assert {:error, :too_short} = BackendAuth.set_password("")
    refute BackendAuth.configured?()
  end

  test "stored password file is owner-only (0600)", %{path: path} do
    assert :ok = BackendAuth.set_password("long-enough-password")
    mode = File.stat!(path).mode &&& 0o777
    assert mode == 0o600
  end

  test "verify accepts the correct password and rejects others" do
    assert :ok = BackendAuth.set_password("correct horse")
    assert BackendAuth.verify("correct horse")
    refute BackendAuth.verify("wrong")
    refute BackendAuth.verify("")
  end

  test "verify is false when no password is configured" do
    refute BackendAuth.verify("anything")
  end

  test "stored hash is salted, not plaintext", %{path: path} do
    assert :ok = BackendAuth.set_password("plaintext-secret")
    content = File.read!(path)
    refute content =~ "plaintext-secret"
    assert content =~ ~r/^pbkdf2\$\d+\$[0-9a-f]+\$[0-9a-f]+$/
  end
end
