defmodule Kakemono.BackendAuth do
  @moduledoc """
  Single-password protection for the backend (control panel + landing page).

  The password is stored as a salted PBKDF2-HMAC-SHA256 hash in a file in the
  data dir (`Kakemono.DataDir.backend_password_file/0`), formatted as
  `pbkdf2$<iterations>$<salt-hex>$<hash-hex>`. There is no username.
  """

  @iterations 120_000
  @salt_bytes 16
  @key_len 32
  @min_password_length 12

  @doc "Minimum accepted backend password length."
  def min_password_length, do: @min_password_length

  @doc "Whether backend auth is active (disabled in test via config)."
  def enabled?, do: Application.get_env(:kakemono, :backend_auth, true)

  @doc "Whether a password has been set."
  def configured? do
    case read_file() do
      {:ok, content} -> String.trim(content) != ""
      _ -> false
    end
  end

  @doc "Hash and persist a new password. Returns :ok or {:error, reason}."
  def set_password(plain) when is_binary(plain) do
    cond do
      String.length(plain) < @min_password_length ->
        {:error, :too_short}

      true ->
        salt = :crypto.strong_rand_bytes(@salt_bytes)
        hash = :crypto.pbkdf2_hmac(:sha256, plain, salt, @iterations, @key_len)

        encoded =
          "pbkdf2$#{@iterations}$#{Base.encode16(salt, case: :lower)}$#{Base.encode16(hash, case: :lower)}"

        case Kakemono.DataDir.backend_password_file() do
          nil ->
            {:error, :no_password_file}

          path ->
            File.mkdir_p!(Path.dirname(path))

            with :ok <- File.write(path, encoded) do
              # Keep the hash unreadable by other local users on a shared host.
              File.chmod(path, 0o600)
            end
        end
    end
  end

  @doc "Constant-time check of a candidate password against the stored hash."
  def verify(plain) when is_binary(plain) do
    with {:ok, content} <- read_file(),
         ["pbkdf2", iter, salt_hex, hash_hex] <- String.split(String.trim(content), "$"),
         {iterations, ""} <- Integer.parse(iter),
         {:ok, salt} <- Base.decode16(salt_hex, case: :mixed),
         {:ok, expected} <- Base.decode16(hash_hex, case: :mixed) do
      candidate = :crypto.pbkdf2_hmac(:sha256, plain, salt, iterations, byte_size(expected))
      Plug.Crypto.secure_compare(candidate, expected)
    else
      _ -> false
    end
  end

  defp read_file do
    case Kakemono.DataDir.backend_password_file() do
      nil -> :error
      path -> File.read(path)
    end
  end
end
