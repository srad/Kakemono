defmodule KakemonoWeb.ControlLive.Settings do
  use KakemonoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:secret, current_secret())
     |> assign(:password_set, Kakemono.BackendAuth.configured?())}
  end

  @impl true
  def handle_event("regenerate", _params, socket) do
    secret = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    if path = Kakemono.DataDir.secret_file() do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, secret)
      # Keep the plaintext secret unreadable by other local users on a shared host.
      File.chmod!(path, 0o600)
    end

    Application.put_env(:kakemono, :api_secret, secret)
    {:noreply, socket |> assign(:secret, secret) |> put_flash(:info, "New secret generated")}
  end

  @impl true
  def handle_event("set_password", %{"password" => password}, socket) do
    case Kakemono.BackendAuth.set_password(String.trim(password)) do
      :ok ->
        {:noreply,
         socket
         |> assign(:password_set, true)
         |> put_flash(:info, "Backend password updated")}

      {:error, :too_short} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Password must be at least #{Kakemono.BackendAuth.min_password_length()} characters"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update password")}
    end
  end

  defp current_secret, do: Application.get_env(:kakemono, :api_secret, "")
  defp secret_key_path, do: Kakemono.DataDir.secret_file() || "disabled in this environment"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6 w-full max-w-2xl">
      <h1 class="text-2xl font-bold">Settings</h1>
      <nav class="flex gap-4 text-blue-600">
        <.link navigate={~p"/c"}>← Control panel</.link>
        <.link navigate={~p"/c/backups"}>Backups</.link>
        <.link href={~p"/logout"} method="delete" class="ml-auto">Logout</.link>
      </nav>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold">Backend password</h2>
        <p class="text-sm text-gray-600">
          Single password (no username) protecting the control panel and landing page. {if @password_set,
            do: "A password is currently set.",
            else: "No password is set yet."}
        </p>
        <form phx-submit="set_password" class="flex items-center gap-3">
          <input
            type="password"
            name="password"
            autocomplete="new-password"
            placeholder="New password"
            class="flex-1 border rounded px-3 py-2 text-sm"
          />
          <button
            type="submit"
            class="shrink-0 bg-primary text-primary-foreground px-3 py-2 rounded text-sm"
          >
            {if @password_set, do: "Change", else: "Set"}
          </button>
        </form>
      </section>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold">API Secret</h2>
        <p class="text-sm text-gray-600">
          Used by displays to authenticate heartbeat and scene-change API calls
          (<code class="font-mono text-xs bg-gray-100 px-1 rounded">x-kakemono-secret</code> header).
        </p>
        <div class="flex items-center gap-3">
          <code class="flex-1 font-mono text-sm bg-gray-100 border rounded px-3 py-2 break-all select-all">
            {@secret}
          </code>
          <button
            phx-click="regenerate"
            data-confirm="Replace the current secret? All displays will need updating."
            class="shrink-0 bg-destructive text-destructive-foreground px-3 py-2 rounded text-sm"
          >
            Regenerate
          </button>
        </div>
        <p class="text-xs text-gray-500">
          Set <code class="font-mono">KAKEMONO_API_SECRET</code> for the startup secret, or
          use Regenerate to update immediately (persisted to <code class="font-mono">{secret_key_path()}</code>).
        </p>
      </section>
    </div>
    """
  end
end
