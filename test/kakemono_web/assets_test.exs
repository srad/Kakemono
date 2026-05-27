defmodule KakemonoWeb.AssetsTest do
  @moduledoc """
  Guards the JS pipeline that powers the display surface.

  These tests exist so the user does not have to manually open a browser
  to discover that the Slideshow hook is missing or the bundle is stale.
  If they fail: from the assets/ directory run `npm run build` (or restart
  `mix phx.server` so the Vite watcher rebuilds).
  """
  use ExUnit.Case, async: true

  @source_app_js Path.expand("../../assets/js/app.js", __DIR__)
  @built_app_js Path.expand("../../priv/static/assets/app.js", __DIR__)

  test "source app.js defines Hooks.Slideshow and wires hooks: Hooks into LiveSocket" do
    src = File.read!(@source_app_js)

    assert src =~ "Slideshow",
           "assets/js/app.js no longer references the Slideshow hook"

    assert src =~ "from \"./hooks/slideshow.js\"",
           "assets/js/app.js no longer imports ./hooks/slideshow.js"

    assert src =~ "hooks: Hooks",
           "assets/js/app.js LiveSocket is not initialised with `hooks: Hooks`"
  end

  test "built priv/static/assets/app.js bundle contains the Slideshow hook" do
    assert File.exists?(@built_app_js),
           "priv/static/assets/app.js is missing. Run `npm run build` in assets/."

    bundle = File.read!(@built_app_js)

    assert bundle =~ "Slideshow",
           """
           priv/static/assets/app.js is stale and does not contain the Slideshow hook.
           Run `npm run build` in assets/ (or restart `mix phx.server` so the Vite
           watcher rebuilds) and reload the browser.
           """
  end

  @vite_config Path.expand("../../assets/vite.config.js", __DIR__)
  @assets_pkg Path.expand("../../assets/package.json", __DIR__)

  test "no Vue / live_vue scaffolding remains in the asset pipeline" do
    src = File.read!(@source_app_js)
    refute src =~ "vue", "assets/js/app.js imports something vue-related"
    refute src =~ "live_vue", "assets/js/app.js imports live_vue"

    vite = File.read!(@vite_config)
    refute vite =~ "vue", "vite.config.js still references vue"
    refute vite =~ "live_vue", "vite.config.js still references live_vue"

    pkg = File.read!(@assets_pkg)
    refute pkg =~ "\"vue\"", "package.json still depends on vue"
    refute pkg =~ "live_vue", "package.json still depends on live_vue"
    refute pkg =~ "@vitejs/plugin-vue", "package.json still depends on @vitejs/plugin-vue"

    refute File.exists?(Path.expand("../../assets/vue", __DIR__)),
           "assets/vue/ directory should be removed"

    refute File.exists?(Path.expand("../../assets/js/server.js", __DIR__)),
           "assets/js/server.js (Vue SSR entry) should be removed"
  end

  describe "clock hook" do
    test "ClockTick is registered in source app.js" do
      src = File.read!("assets/js/app.js")
      assert src =~ "ClockTick"
    end
  end

  describe "grid editor hook" do
    test "uses a fixed dashboard board with full resize handles" do
      src = File.read!("assets/js/hooks/grid_editor.js")

      assert src =~ "row: ROWS"
      assert src =~ ~s|resizable: { handles: "n,e,s,w,ne,se,sw,nw" }|
      assert src =~ "_updateStyles?.(true, ROWS)"
      assert src =~ "this.el.dataset.orientation || \"portrait\""
      assert src =~ "this.el.dataset.colorScheme || \"light\""
    end

    test "dashboard editor CSS includes surface and dot handle styles" do
      css = File.read!("assets/css/app.css")

      assert css =~ ".dashboard-editor-surface"
      assert css =~ ~s|[data-color-scheme="dark"]|
      assert css =~ ".dashboard-widget-preview"
      assert css =~ ".dashboard-editor-surface .grid-stack-item > .ui-resizable-handle"
    end
  end
end
