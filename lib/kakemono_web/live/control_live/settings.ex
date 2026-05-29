defmodule KakemonoWeb.ControlLive.Settings do
  use KakemonoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_nav, :settings)
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
    <div class="max-w-3xl space-y-6">
      <div>
        <p class="text-sm font-medium text-slate-500">Administration</p>
        <h1 class="text-2xl font-semibold tracking-tight text-slate-950">Settings</h1>
      </div>

      <section class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-slate-950">Backend password</h2>
          <p class="text-sm text-slate-500">
            Single password protecting the control panel and landing page. {if @password_set,
              do: "A password is currently set.",
              else: "No password is set yet."}
          </p>
        </div>
        <form phx-submit="set_password" class="flex flex-col gap-3 sm:flex-row">
          <input
            type="password"
            name="password"
            autocomplete="new-password"
            placeholder="New password"
            class="flex-1 rounded-md border-slate-300 text-sm shadow-sm focus:border-slate-500 focus:ring-slate-500"
          />
          <button
            type="submit"
            class="inline-flex h-10 shrink-0 items-center justify-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800"
          >
            {if @password_set, do: "Change", else: "Set"}
          </button>
        </form>
      </section>

      <section class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-slate-950">API Secret</h2>
          <p class="text-sm text-slate-500">
            Used by displays to authenticate heartbeat and scene-change API calls
            (<code class="rounded bg-slate-100 px-1 font-mono text-xs">x-kakemono-secret</code> header).
          </p>
        </div>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start">
          <code class="flex-1 select-all break-all rounded-md border border-slate-200 bg-slate-50 px-3 py-2 font-mono text-sm text-slate-700">
            {@secret}
          </code>
          <button
            phx-click="regenerate"
            data-confirm="Replace the current secret? All displays will need updating."
            class="inline-flex h-10 shrink-0 items-center justify-center rounded-md bg-rose-600 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-rose-700"
          >
            Regenerate
          </button>
        </div>
        <p class="mt-3 text-xs text-slate-500">
          Set <code class="font-mono">KAKEMONO_API_SECRET</code> for the startup secret, or
          use Regenerate to update immediately (persisted to <code class="font-mono">{secret_key_path()}</code>).
        </p>
      </section>
    </div>
    """
  end
end
