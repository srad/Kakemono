defmodule Kakemono.WidgetsTest do
  use Kakemono.DataCase, async: false
  alias Kakemono.{Scenes, Widgets}
  alias Kakemono.Widgets.Registry

  setup do
    {:ok, scene} = Scenes.create(%{name: "T", mode: "dashboard", layout: %{"cells" => []}})
    %{scene: scene}
  end

  describe "registry" do
    test "lists clock + weather as known types" do
      types = Registry.types() |> Enum.sort()
      assert "clock" in types
      assert "weather" in types
    end

    test "fetch/1 returns the module for a type" do
      assert Registry.fetch("clock") == Kakemono.Widgets.Clock
      assert Registry.fetch("weather") == Kakemono.Widgets.Weather
      assert Registry.fetch("nope") == nil
    end

    test "clock styles expose celestial, lunar, and minimal" do
      style_enum = Kakemono.Widgets.Clock.config_schema()["properties"]["style"]["enum"]
      style_field = Enum.find(Kakemono.Widgets.Clock.config_fields(), &(&1.key == "style"))
      labels = Enum.map(style_field.options, fn {_value, label} -> label end)

      assert Enum.sort(style_enum) == ["celestial", "lunar", "minimal"]
      refute "atmosphere" in style_enum
      assert labels == ["Celestial", "Lunar", "Minimal"]
      refute "Day Cycle" in labels
    end
  end

  describe "create_instance/3" do
    test "merges defaults and persists", %{scene: scene} do
      assert {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})
      assert inst.widget_type == "clock"
      assert inst.config["format"] == "24h"
      assert inst.scene_id == scene.id
    end

    test "rejects unknown widget type", %{scene: scene} do
      assert {:error, :unknown_widget_type} = Widgets.create_instance("bogus", scene.id, %{})
    end

    test "rejects config that violates the schema", %{scene: scene} do
      assert {:error, {:invalid_config, _errors}} =
               Widgets.create_instance("clock", scene.id, %{"format" => "37h"})
    end

    test "weather requires lat/long", %{scene: scene} do
      assert {:ok, w} = Widgets.create_instance("weather", scene.id, %{"label" => "Home"})
      assert w.config["label"] == "Home"
      assert w.config["latitude"] == 0.0

      assert {:error, {:invalid_config, _}} =
               Widgets.create_instance("weather", scene.id, %{"latitude" => 999.0})
    end
  end

  describe "create_draft_instance/3" do
    test "persists default config before required fields are filled", %{scene: scene} do
      assert {:error, {:invalid_config, _}} = Widgets.create_instance("rss", scene.id, %{})

      assert {:ok, inst} = Widgets.create_draft_instance("rss", scene.id, %{})
      assert inst.widget_type == "rss"
      assert inst.config == %{"max_items" => 5}
    end

    test "uses a blank editor template when defaults are placeholders", %{scene: scene} do
      assert {:ok, strict} = Widgets.create_instance("weather", scene.id, %{})
      assert strict.config["label"] == "Weather"
      assert strict.config["latitude"] == 0.0

      assert {:ok, draft} = Widgets.create_draft_instance("weather", scene.id, %{})
      assert draft.config == %{}
    end
  end

  describe "list_instances_for/1" do
    test "only returns instances of the given scene", %{scene: a} do
      {:ok, b} = Scenes.create(%{name: "B", mode: "dashboard", layout: %{"cells" => []}})

      {:ok, a1} = Widgets.create_instance("clock", a.id, %{})
      {:ok, _b1} = Widgets.create_instance("clock", b.id, %{})

      assert [%{id: id}] = Widgets.list_instances_for(a.id)
      assert id == a1.id
    end
  end

  describe "update_config/2" do
    test "merges and re-validates", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})
      assert {:ok, updated} = Widgets.update_config(inst, %{"show_seconds" => true})
      assert updated.config["show_seconds"] == true
      assert updated.config["format"] == "24h"
    end

    test "rejects invalid config on update", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})

      assert {:error, {:invalid_config, _}} =
               Widgets.update_config(inst, %{"format" => "garbage"})
    end
  end

  describe "delete_instance/1" do
    test "removes the row", %{scene: scene} do
      {:ok, inst} = Widgets.create_instance("clock", scene.id, %{})
      assert {:ok, _} = Widgets.delete_instance(inst)
      assert Widgets.get_instance(inst.id) == nil
    end
  end
end
