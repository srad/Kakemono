defmodule KakemonoWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use KakemonoWeb, :controller` and
  `use KakemonoWeb, :live_view`.
  """
  use KakemonoWeb, :html

  attr :active, :atom, default: nil

  def backend_nav(assigns) do
    assigns =
      assign(assigns, :items, [
        %{label: "Control", path: ~p"/c", icon: "hero-squares-2x2", key: :control},
        %{label: "Media", path: ~p"/c/media", icon: "hero-photo", key: :media},
        %{label: "Playlists", path: ~p"/c/playlists", icon: "hero-queue-list", key: :playlists},
        %{label: "Scenes", path: ~p"/c/scenes", icon: "hero-rectangle-group", key: :scenes},
        %{label: "Settings", path: ~p"/c/settings", icon: "hero-cog-6-tooth", key: :settings},
        %{label: "Backups", path: ~p"/c/backups", icon: "hero-archive-box", key: :backups}
      ])

    ~H"""
    <header class="sticky top-0 z-40 border-b border-slate-200/80 bg-white/95 shadow-sm backdrop-blur">
      <div class="mx-auto flex min-h-16 max-w-7xl flex-col gap-3 px-4 py-3 sm:px-6 lg:flex-row lg:items-center lg:justify-between lg:gap-6">
        <div class="flex items-center justify-between gap-4">
          <.link navigate={~p"/c"} class="flex items-center gap-3">
            <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-slate-950 text-sm font-semibold text-white">
              K
            </span>
            <span>
              <span class="block text-sm font-semibold leading-5 text-slate-950">Kakemono</span>
              <span class="block text-xs leading-4 text-slate-500">Backend</span>
            </span>
          </.link>
          <.link
            href={~p"/logout"}
            method="delete"
            class="inline-flex items-center gap-1.5 rounded-md border border-slate-200 px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-300 hover:bg-slate-50 lg:hidden"
          >
            <.icon name="hero-arrow-left-on-rectangle" class="h-4 w-4" /> Logout
          </.link>
        </div>

        <nav
          class="flex min-w-0 flex-1 items-center gap-1 overflow-x-auto"
          aria-label="Backend navigation"
        >
          <.link
            :for={item <- @items}
            navigate={item.path}
            class={[
              "inline-flex shrink-0 items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition",
              if(@active == item.key,
                do: "bg-slate-950 text-white shadow-sm",
                else: "text-slate-600 hover:bg-slate-100 hover:text-slate-950"
              )
            ]}
            aria-current={if @active == item.key, do: "page", else: nil}
          >
            <.icon name={item.icon} class="h-4 w-4" />
            {item.label}
          </.link>
        </nav>

        <.link
          href={~p"/logout"}
          method="delete"
          class="hidden items-center gap-2 rounded-md border border-slate-200 px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-300 hover:bg-slate-50 lg:inline-flex"
        >
          <.icon name="hero-arrow-left-on-rectangle" class="h-4 w-4" /> Logout
        </.link>
      </div>
    </header>
    """
  end

  embed_templates "layouts/*"
end
