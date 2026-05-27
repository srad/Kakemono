defmodule Kakemono.Widgets.Rss do
  @behaviour Kakemono.Widget
  use Phoenix.Component

  @impl true
  def type, do: "rss"

  @impl true
  def name, do: "Feed"

  @impl true
  def config_schema do
    %{
      "type" => "object",
      "required" => ["url"],
      "properties" => %{
        "url" => %{"type" => "string", "minLength" => 1},
        "title" => %{"type" => "string"},
        "max_items" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
        "cached_items" => %{"type" => "array"},
        "feed_title" => %{"type" => "string"}
      },
      "additionalProperties" => false
    }
  end

  @impl true
  def default_config, do: %{"max_items" => 5}

  @impl true
  def prefetch(%Kakemono.Widgets.Instance{id: id, config: cfg}) do
    url = cfg["url"]
    items = cfg["cached_items"]

    if is_binary(url) and url != "" and (is_nil(items) or items == []) do
      %{instance_id: id}
      |> Kakemono.Widgets.RssFetchWorker.new()
      |> Oban.insert!()
    end

    :ok
  end

  @impl true
  def config_fields do
    [
      %{
        key: "url",
        label: "Feed URL",
        type: :text,
        required: true,
        placeholder: "https://feeds.example.com/rss"
      },
      %{
        key: "title",
        label: "Display title",
        type: :text,
        required: false,
        placeholder: "— use feed title —"
      },
      %{
        key: "max_items",
        label: "Max items",
        type: :number,
        required: false,
        integer: true,
        min: 1,
        max: 20,
        step: "1",
        placeholder: "5"
      }
    ]
  end

  @doc "Parse RSS or Atom XML bytes into a list of item maps."
  def parse_feed(body) when is_binary(body) do
    import SweetXml

    try do
      rss_items =
        body
        |> xpath(
          ~x"//item"l,
          title: ~x"./title/text()"s,
          link: ~x"./link/text()"s,
          pub_date: ~x"./pubDate/text()"s
        )

      if rss_items != [] do
        feed_title = body |> xpath(~x"//channel/title/text()"s)
        {to_string(feed_title), normalize_items(rss_items)}
      else
        atom_items =
          body
          |> xpath(
            ~x"//entry"l,
            title: ~x"./title/text()"s,
            link: ~x"./link/@href"s,
            updated: ~x"./updated/text()"s,
            published: ~x"./published/text()"s
          )
          |> Enum.map(fn i ->
            date = if i.updated != "", do: i.updated, else: i.published
            %{title: i.title, link: i.link, pub_date: date}
          end)

        feed_title = body |> xpath(~x"/*[local-name()='feed']/*[local-name()='title']/text()"s)
        {to_string(feed_title), normalize_items(atom_items)}
      end
    catch
      :exit, _ -> {"", []}
    end
  end

  defp normalize_items(items) do
    Enum.map(items, fn i ->
      %{
        "title" => to_string(i.title) |> String.trim(),
        "link" => to_string(i.link) |> String.trim(),
        "pub_date" => to_string(i.pub_date) |> String.trim()
      }
    end)
    |> Enum.reject(&(&1["title"] == ""))
  end

  @impl true
  def render(assigns) do
    cfg = assigns.instance.config
    display_title = cfg["title"] || cfg["feed_title"] || "Feed"
    max = cfg["max_items"] || 5
    items = Enum.take(cfg["cached_items"] || [], max)

    assigns = Map.merge(assigns, %{display_title: display_title, items: items})

    ~H"""
    <div class="kakemono-widget kakemono-widget-rss">
      <div class="kw-rss-header">
        <span class="kw-rss-feed-icon" aria-hidden="true">
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M4 4a16 16 0 0 1 16 16"
              stroke="currentColor"
              stroke-width="2.6"
              stroke-linecap="round"
            />
            <path
              d="M4 10a10 10 0 0 1 10 10"
              stroke="currentColor"
              stroke-width="2.6"
              stroke-linecap="round"
            />
            <circle cx="5.6" cy="18.6" r="2" fill="currentColor" />
          </svg>
        </span>
        <span class="kw-rss-title">{@display_title}</span>
      </div>
      <div :if={@items == []} class="kw-rss-empty">No items cached yet.</div>
      <ul :if={@items != []} class="kw-rss-list">
        <li :for={item <- @items} class="kw-rss-row">
          <a class="kw-rss-link" href={item["link"]} target="_blank" rel="noopener noreferrer">
            <span class="kw-rss-text">{item["title"]}</span>
            <span :if={meta_for(item) != ""} class="kw-rss-date">{meta_for(item)}</span>
          </a>
        </li>
      </ul>
    </div>
    """
  end

  defp meta_for(item) do
    item |> Map.get("pub_date", "") |> to_string() |> format_pub_date()
  end

  defp format_pub_date(""), do: ""
  defp format_pub_date(nil), do: ""

  defp format_pub_date(str) when is_binary(str) do
    cond do
      match = Regex.run(~r/^(\w{3}), (\d{1,2}) (\w{3}) (\d{4})/, str) ->
        [_, _wday, day, mon, year] = match
        "#{day} #{mon} #{year}"

      match = Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})/, str) ->
        [_, year, month, day] = match
        "#{day}.#{month}.#{year}"

      true ->
        str
    end
  end
end
