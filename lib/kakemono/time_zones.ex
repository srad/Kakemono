defmodule Kakemono.TimeZones do
  @moduledoc "IANA time zone names available to widget configuration."

  @zoneinfo_dir "/usr/share/zoneinfo"
  @tab_files ["zone1970.tab", "zone.tab"]
  @fixed_zones ~w(UTC Etc/UTC)

  # Used when the OS tzdata package is unavailable. Containers install tzdata,
  # so normal deployments use the complete system list.
  @fallback_zones ~w(
    Africa/Cairo
    Africa/Johannesburg
    America/Chicago
    America/Denver
    America/Los_Angeles
    America/New_York
    America/Sao_Paulo
    Asia/Dubai
    Asia/Hong_Kong
    Asia/Kolkata
    Asia/Seoul
    Asia/Shanghai
    Asia/Singapore
    Asia/Tokyo
    Australia/Melbourne
    Australia/Sydney
    Europe/Amsterdam
    Europe/Berlin
    Europe/London
    Europe/Madrid
    Europe/Paris
    Pacific/Auckland
  )

  def list do
    zones = @fixed_zones ++ tab_zones()

    zones =
      if zones == @fixed_zones do
        zones ++ @fallback_zones
      else
        zones
      end

    zones
    |> Enum.uniq()
    |> Enum.sort()
  end

  def valid?(zone) when is_binary(zone) do
    zone = String.trim(zone)
    zone != "" and zone in list()
  end

  def valid?(_), do: false

  defp tab_zones do
    @tab_files
    |> Enum.flat_map(fn file ->
      @zoneinfo_dir
      |> Path.join(file)
      |> parse_tab_file()
    end)
  end

  defp parse_tab_file(path) do
    if File.regular?(path) do
      path
      |> File.stream!([], :line)
      |> Stream.reject(&String.starts_with?(&1, "#"))
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.map(&zone_from_tab_line/1)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp zone_from_tab_line(line) do
    case String.split(line, "\t") do
      [_countries, _coordinates, zone | _rest] -> zone
      _ -> nil
    end
  end
end
