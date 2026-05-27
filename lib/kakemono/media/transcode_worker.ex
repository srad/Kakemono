defmodule Kakemono.Media.TranscodeWorker do
  use Oban.Worker, queue: :media, max_attempts: 3

  alias Kakemono.Media
  alias Kakemono.Media.Item

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"id" => id}}) do
    case Media.get_item(id) do
      nil -> :ok
      item -> process(item)
    end
  end

  defp process(%Item{} = item) do
    src = Media.absolute_path(item)

    try do
      unless File.exists?(src), do: raise("source file missing: #{src}")

      attrs =
        cond do
          item.mime_type in ["image/heic", "image/heif"] or
              String.ends_with?(String.downcase(item.filename), [".heic", ".heif"]) ->
            transcode_heic(item, src)

          String.starts_with?(item.mime_type, "image/") ->
            process_image(item, src)

          String.starts_with?(item.mime_type, "video/") ->
            process_video(item, src)

          true ->
            %{status: "ready"}
        end

      thumb = make_thumbnail(item, Map.get(attrs, :filename, item.filename))
      attrs = Map.put(attrs, :thumbnail_path, thumb)
      attrs = Map.put(attrs, :status, "ready")

      {:ok, _} = Media.update(item, attrs)
      :ok
    rescue
      e ->
        Logger.error("transcode failed for #{item.filename}: #{Exception.message(e)}")
        {:ok, _} = Media.update(item, %{status: "failed"})
        :ok
    end
  end

  defp transcode_heic(item, src) do
    new_name = Path.rootname(item.filename) <> ".jpg"
    dst = Path.join(Media.uploads_dir(), new_name)
    {:ok, img} = Image.open(src)
    {:ok, _} = Image.write(img, dst, quality: 85)
    _ = File.rm(src)
    {w, h} = dims_safe(dst)
    %{filename: new_name, mime_type: "image/jpeg", width: w, height: h}
  end

  defp process_image(_item, src) do
    {w, h} = dims_safe(src)
    %{width: w, height: h}
  end

  defp process_video(item, src) do
    # Detect codec and transcode to H.264 if not already.
    codec = video_codec(src)

    if codec == "h264" do
      duration_ms = video_duration_ms(src)
      {w, h} = video_dims(src)
      %{duration_ms: duration_ms, width: w, height: h}
    else
      new_name = Path.rootname(item.filename) <> ".mp4"
      dst = Path.join(Media.uploads_dir(), new_name)

      {_, 0} =
        System.cmd(
          "ffmpeg",
          [
            "-y",
            "-i",
            src,
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "22",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
            "-movflags",
            "+faststart",
            dst
          ],
          stderr_to_stdout: true
        )

      _ = File.rm(src)
      duration_ms = video_duration_ms(dst)
      {w, h} = video_dims(dst)
      %{filename: new_name, mime_type: "video/mp4", duration_ms: duration_ms, width: w, height: h}
    end
  end

  defp make_thumbnail(_item, filename) do
    _ = Media.thumb_dir()
    src = Path.join(Media.uploads_dir(), filename)
    thumb_name = "thumbs/" <> Path.rootname(filename) <> ".jpg"
    dst = Path.join(Media.uploads_dir(), thumb_name)

    cond do
      String.match?(filename, ~r/\.(jpe?g|png|webp|gif|tiff?)$/i) ->
        case Image.open(src) do
          {:ok, img} ->
            {:ok, resized} = Image.thumbnail(img, 400)
            {:ok, _} = Image.write(resized, dst, quality: 80)
            thumb_name

          _ ->
            nil
        end

      String.match?(filename, ~r/\.(mp4|mov|mkv|webm)$/i) ->
        {_, code} =
          System.cmd(
            "ffmpeg",
            [
              "-y",
              "-i",
              src,
              "-vframes",
              "1",
              "-vf",
              "scale=400:-1",
              dst
            ],
            stderr_to_stdout: true
          )

        if code == 0, do: thumb_name, else: nil

      true ->
        nil
    end
  rescue
    e ->
      Logger.error("thumbnail failed: #{Exception.message(e)}")
      nil
  end

  defp dims_safe(path) do
    case Image.open(path) do
      {:ok, img} -> {Image.width(img), Image.height(img)}
      _ -> {nil, nil}
    end
  rescue
    _ -> {nil, nil}
  end

  defp video_codec(path) do
    {out, 0} =
      System.cmd(
        "ffprobe",
        [
          "-v",
          "error",
          "-select_streams",
          "v:0",
          "-show_entries",
          "stream=codec_name",
          "-of",
          "default=nokey=1:noprint_wrappers=1",
          path
        ],
        stderr_to_stdout: true
      )

    String.trim(out)
  rescue
    _ -> "unknown"
  end

  defp video_duration_ms(path) do
    {out, 0} =
      System.cmd(
        "ffprobe",
        [
          "-v",
          "error",
          "-show_entries",
          "format=duration",
          "-of",
          "default=nokey=1:noprint_wrappers=1",
          path
        ],
        stderr_to_stdout: true
      )

    case Float.parse(String.trim(out)) do
      {s, _} -> round(s * 1000)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp video_dims(path) do
    {out, 0} =
      System.cmd(
        "ffprobe",
        [
          "-v",
          "error",
          "-select_streams",
          "v:0",
          "-show_entries",
          "stream=width,height",
          "-of",
          "csv=s=x:p=0",
          path
        ],
        stderr_to_stdout: true
      )

    case String.trim(out) |> String.split("x") do
      [w, h] -> {String.to_integer(w), String.to_integer(h)}
      _ -> {nil, nil}
    end
  rescue
    _ -> {nil, nil}
  end
end
