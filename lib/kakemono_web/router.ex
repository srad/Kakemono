defmodule KakemonoWeb.Router do
  use KakemonoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KakemonoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :set_backend_locale
  end

  pipeline :display do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KakemonoWeb.Layouts, :display}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug KakemonoWeb.Plugs.ApiAuth
  end

  pipeline :backend_auth do
    plug KakemonoWeb.Plugs.BackendAuth
  end

  scope "/", KakemonoWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", KakemonoWeb do
    pipe_through [:browser, :backend_auth]

    get "/", PageController, :home
  end

  scope "/c", KakemonoWeb do
    pipe_through [:browser, :backend_auth]

    live_session :authenticated,
                 on_mount: [
                   {KakemonoWeb.BackendAuth, :ensure_authed},
                   {KakemonoWeb.LocaleHook, :backend}
                 ] do
      live "/", ControlLive.Index, :index
      live "/media", MediaLive.Index, :index
      live "/playlists", PlaylistsLive.Index, :index
      live "/playlists/:id", PlaylistsLive.Edit, :edit
      live "/calendars", CalendarsLive.Index, :index
      live "/calendars/:id", CalendarsLive.Edit, :edit
      live "/scenes", ScenesLive.Index, :index
      live "/scenes/:id", ScenesLive.Edit, :edit
      live "/settings", ControlLive.Settings, :index
      live "/backups", ControlLive.Backups, :index
    end

    get "/backups/:filename/download", BackupController, :download
  end

  scope "/d", KakemonoWeb do
    pipe_through :display
    live "/:display_id", DisplayLive.Index, :index
  end

  scope "/api", KakemonoWeb.Api do
    pipe_through [:api, :api_auth]

    post "/displays/:id/heartbeat", DisplayController, :heartbeat
    post "/displays/:id/scene", DisplayController, :set_scene
    get "/displays/:id", DisplayController, :state
  end

  defp set_backend_locale(conn, _opts) do
    Gettext.put_locale(KakemonoWeb.Gettext, Kakemono.Locale.get())
    conn
  end

  if Application.compile_env(:kakemono, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KakemonoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
