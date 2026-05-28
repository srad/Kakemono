defmodule Kakemono.Widget.ConfigTest do
  @moduledoc """
  Guards that each widget's derived `config_schema/0` and `default_config/0`
  (generated from its `fields/0` + `cache_fields/0`) match the schemas/defaults
  that were previously hand-written. Catches drift in the field->schema
  generator.
  """
  use ExUnit.Case, async: true

  alias Kakemono.Widgets.{AirQuality, Clock, Instagram, Rss, Slideshow, Weather}

  describe "derived config_schema/0 matches the pre-refactor schema" do
    test "clock" do
      assert Clock.config_schema() == %{
               "type" => "object",
               "additionalProperties" => false,
               "properties" => %{
                 "title" => %{"type" => "string"},
                 "style" => %{"type" => "string", "enum" => ["celestial", "lunar", "minimal"]},
                 "format" => %{"type" => "string", "enum" => ["24h", "12h"]},
                 "show_seconds" => %{"type" => "boolean"},
                 "timezone" => %{"type" => "string", "enum" => Kakemono.TimeZones.list()}
               }
             }
    end

    test "weather" do
      assert Weather.config_schema() == %{
               "type" => "object",
               "required" => ["latitude", "longitude"],
               "additionalProperties" => false,
               "properties" => %{
                 "latitude" => %{"type" => "number", "minimum" => -90, "maximum" => 90},
                 "longitude" => %{"type" => "number", "minimum" => -180, "maximum" => 180},
                 "label" => %{"type" => "string"},
                 "source" => %{
                   "type" => "string",
                   "enum" => ["open_meteo", "met_no", "bright_sky"]
                 },
                 "api_key" => %{"type" => "string"},
                 "cached" => %{"type" => "object"}
               }
             }
    end

    test "air_quality" do
      assert AirQuality.config_schema() == %{
               "type" => "object",
               "required" => ["latitude", "longitude"],
               "additionalProperties" => false,
               "properties" => %{
                 "latitude" => %{"type" => "number", "minimum" => -90, "maximum" => 90},
                 "longitude" => %{"type" => "number", "minimum" => -180, "maximum" => 180},
                 "label" => %{"type" => "string"},
                 "cached" => %{"type" => "object"},
                 "fetched_at" => %{"type" => "string"}
               }
             }
    end

    test "rss" do
      assert Rss.config_schema() == %{
               "type" => "object",
               "required" => ["url"],
               "additionalProperties" => false,
               "properties" => %{
                 "url" => %{"type" => "string", "minLength" => 1},
                 "title" => %{"type" => "string"},
                 "max_items" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
                 "cached_items" => %{"type" => "array"},
                 "feed_title" => %{"type" => "string"},
                 "fetched_at" => %{"type" => "string"}
               }
             }
    end

    test "slideshow" do
      assert Slideshow.config_schema() == %{
               "type" => "object",
               "required" => ["playlist_id"],
               "additionalProperties" => false,
               "properties" => %{
                 "playlist_id" => %{"type" => "integer", "minimum" => 1},
                 "interval_ms" => %{"type" => "integer", "minimum" => 2000},
                 "fit_mode" => %{"type" => "string", "enum" => ["contain", "cover"]}
               }
             }
    end

    test "instagram" do
      assert Instagram.config_schema() == %{
               "type" => "object",
               "required" => ["username"],
               "additionalProperties" => false,
               "properties" => %{
                 "username" => %{"type" => "string", "minLength" => 1},
                 "access_token" => %{"type" => "string", "minLength" => 1},
                 "max_items" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
                 "interval_ms" => %{"type" => "integer", "minimum" => 2000},
                 "fit_mode" => %{"type" => "string", "enum" => ["contain", "cover"]},
                 "cached_items" => %{"type" => "array"},
                 "last_error" => %{"type" => "string"},
                 "last_error_at" => %{"type" => "string"},
                 "last_fetch_at" => %{"type" => "string"},
                 "next_fetch_at" => %{"type" => "string"}
               }
             }
    end
  end

  describe "derived default_config/0 matches the pre-refactor defaults" do
    test "all widgets" do
      assert Clock.default_config() == %{
               "style" => "celestial",
               "format" => "24h",
               "show_seconds" => false
             }

      assert Weather.default_config() == %{
               "latitude" => 0.0,
               "longitude" => 0.0,
               "label" => "Weather",
               "source" => "open_meteo"
             }

      assert AirQuality.default_config() == %{
               "latitude" => 0.0,
               "longitude" => 0.0,
               "label" => "Air Quality"
             }

      assert Rss.default_config() == %{"max_items" => 5}
      assert Slideshow.default_config() == %{}
      assert Instagram.default_config() == %{"max_items" => 9}
    end

    test "weather and air_quality start drafts empty" do
      assert Weather.draft_config() == %{}
      assert AirQuality.draft_config() == %{}
    end
  end
end
