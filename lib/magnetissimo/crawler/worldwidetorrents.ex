defmodule Magnetissimo.Crawler.WorldWideTorrents do
  use GenServer
  alias Magnetissimo.Torrent
  import Magnetissimo.Crawler.Helper
  require Logger

  def start_link(_) do
    queue = initial_queue()
    GenServer.start_link(__MODULE__, queue, name: __MODULE__)
  end

  def init(queue) do
    Logger.info IO.ANSI.magenta <> "Starting WorldWideTorrents crawler" <> IO.ANSI.reset
    schedule_work()
    {:ok, queue}
  end

  defp schedule_work do
    Process.send_after(self(), :work, 1 * 1 * 100) # 5 seconds
  end

  # Callbacks

  def handle_info(:work, queue) do
    new_queue =
      case :queue.out(queue) do
        {{_value, item}, queue_2} ->
          process(item, queue_2)
        _ ->
          Logger.info "[WorldWideTorrents] Queue is empty, restarting scraping procedure."
          initial_queue()
      end
    schedule_work()
    {:noreply, new_queue}
  end

  def process({:page_link, url}, queue) do
    Logger.info "[WorldWideTorrents] Finding torrents in listing page: #{url}"
    html_body = download(url)
    if html_body != nil do
      torrent_information(html_body)
      |> Enum.each(fn(torrent) -> Torrent.save_torrent(torrent) end)
    end
    queue
  end

  # Parser functions

  # WorldWideTorrents offers all of it's content on it's pagination page.
  # There's no need to go into a torrent detail page.
  def initial_queue do
    urls = for i <- 1..50 do
      {:page_link, "https://worldwidetorrents.eu/torrents.php?page=#{i}"}
    end
    :queue.from_list(urls)
  end

  def torrent_information(html_body) do
    torrents = html_body
      |> Floki.find(".ttable_headinner .t-row")
      |> Enum.map(fn(row) -> parse_row(row) end)
    torrents
  end

  def parse_row(row) do
    name = row
      |> Floki.find("td")
      |> Enum.at(0)
      |> Floki.find("a b")
      |> Floki.text
      |> String.trim

    magnet = row
      |> Floki.find("a")
      |> Floki.attribute("href")
      |> Enum.filter(fn(url) -> String.starts_with?(url, "magnet:") end)
      |> Enum.at(0)

    size_html = row
      |> Floki.find("td")
      |> Enum.at(4)
      |> Floki.text
      |> String.replace(",", "")
      |> String.split
    size_value = Enum.at(size_html, 0)
    unit = Enum.at(size_html, 1)
    size = size_to_bytes(size_value, unit) |> Kernel.to_string

    seeders = row
      |> Floki.find("td")
      |> Enum.at(5)
      |> Floki.text
      |> String.replace(",", "")

    leechers = row
      |> Floki.find("td")
      |> Enum.at(6)
      |> Floki.text
      |> String.replace(",", "")

    %{
      name: name,
      magnet: magnet,
      size: size,
      website_source: "worldwidetorrents",
      seeders: seeders,
      leechers: leechers
    }
  end
end
