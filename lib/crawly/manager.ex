defmodule Crawly.Manager do
  @moduledoc """
  Crawler manager module

  This module is responsible for spawning all processes related to
  a given Crawler.

  The manager spawns the following processes tree.
  ┌────────────────┐        ┌───────────────────┐
  │ Crawly.Manager ├────────> Crawly.ManagerSup │
  └────────────────┘        └─────────┬─────────┘
           │                          |
           │                          |
           ┌──────────────────────────┤
           │                          │
           │                          │
  ┌────────▼───────┐        ┌─────────▼───────┐
  │    Worker1     │        │    Worker2      │
  └────────┬───────┘        └────────┬────────┘
           │                         │
           │                         │
           │                         │
           │                         │
  ┌────────▼─────────┐    ┌──────────▼───────────┐
  │Crawly.DataStorage│    │Crawly.RequestsStorage│
  └──────────────────┘    └──────────────────────┘
  """
  require Logger

  @timeout 60_000

  use GenServer

  alias Crawly.Utils

  def start_link(spider_name) do
    Logger.debug("Starting the manager for #{spider_name}")
    GenServer.start_link(__MODULE__, spider_name)
  end

  def init(spider_name) do
    # Getting spider start urls
    [start_urls: urls, device_type: device_type] = spider_name.init()

    # Start DataStorage worker
    {:ok, data_storage_pid} = Crawly.DataStorage.start_worker(spider_name)
    Process.link(data_storage_pid)

    # Start RequestsWorker for a given spider
    {:ok, request_storage_pid} =
      Crawly.RequestsStorage.start_worker(spider_name)

    Process.link(request_storage_pid)

    # Store start requests
    requests =
      Enum.map(urls, fn url ->
        Crawly.Request.new(
          url,
          device_type: device_type
        )
      end)

    :ok = Crawly.RequestsStorage.store(spider_name, requests)

    # Start workers
    num_workers =
      Utils.get_settings(:concurrent_requests_per_domain, spider_name, 4)

    worker_pids =
      Enum.map(1..num_workers, fn _x ->
        DynamicSupervisor.start_child(
          spider_name,
          {Crawly.Worker, [spider_name]}
        )
      end)

    Logger.debug(
      "Started #{Enum.count(worker_pids)} workers for #{spider_name}"
    )

    # Schedule basic service operations for given spider manager
    timeout =
      Utils.get_settings(:manager_operations_timeout, spider_name, @timeout)

    tref = Process.send_after(self(), :operations, timeout)

    {:ok,
     %{name: spider_name, tref: tref, prev_scraped_cnt: 0, workers: worker_pids}}
  end

  def handle_info(:operations, state) do
    Process.cancel_timer(state.tref)

    # Close spider if required items count was reached.
    {:stored_items, items_count} = Crawly.DataStorage.stats(state.name)

    delta = items_count - state.prev_scraped_cnt
    Logger.info("Current crawl speed is: #{delta} items/min")

    itemcount_limit =
      :closespider_itemcount
      |> Utils.get_settings(state.name)
      |> maybe_convert_to_integer()

    maybe_stop_spider_by_itemcount_limit(
      state.name,
      items_count,
      itemcount_limit
    )

    # Close spider in case if it's not scraping items fast enough
    closespider_timeout_limit =
      :closespider_timeout
      |> Utils.get_settings(state.name)
      |> maybe_convert_to_integer()

    maybe_stop_spider_by_timeout(
      state.name,
      delta,
      closespider_timeout_limit
    )

    tref =
      Process.send_after(
        self(),
        :operations,
        Utils.get_settings(:manager_operations_timeout, state.name, @timeout)
      )

    {:noreply, %{state | tref: tref, prev_scraped_cnt: items_count}}
  end

  defp maybe_stop_spider_by_itemcount_limit(spider_name, current, limit)
       when current > limit do
    Logger.info(
      "Stopping #{inspect(spider_name)}, closespider_itemcount achieved"
    )

    Crawly.Engine.stop_spider(spider_name, :itemcount_limit)
  end

  defp maybe_stop_spider_by_itemcount_limit(_, _, _), do: :ok

  defp maybe_stop_spider_by_timeout(spider_name, current, limit)
       when current < limit do
    Logger.info("Stopping #{inspect(spider_name)}, itemcount timeout achieved")

    Crawly.Engine.stop_spider(spider_name, :itemcount_timeout)
  end

  defp maybe_stop_spider_by_timeout(_, _, _), do: :ok

  defp maybe_convert_to_integer(value) when is_atom(value), do: value

  defp maybe_convert_to_integer(value) when is_binary(value),
    do: String.to_integer(value)

  defp maybe_convert_to_integer(value) when is_integer(value), do: value
end
