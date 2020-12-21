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
  @start_request_split_size 50

  use GenServer

  alias Crawly.{Engine, Utils}

  @spec add_workers(module(), non_neg_integer()) ::
          :ok | {:error, :spider_non_exist}
  def add_workers(spider_name, num_of_workers) do
    case Engine.get_manager(spider_name) do
      {:error, reason} ->
        {:error, reason}

      pid ->
        GenServer.cast(pid, {:add_workers, num_of_workers})
    end
  end

  def start_link([spider_name, options]) do
    Logger.debug("Starting the manager for #{spider_name}")
    GenServer.start_link(__MODULE__, [spider_name, options])
  end

  @impl true
  def init([spider_name, options]) do
    crawl_id = Keyword.get(options, :crawl_id)
    Logger.metadata(spider_name: spider_name, crawl_id: crawl_id)
    # Start DataStorage worker
    {:ok, data_storage_pid} =
      Crawly.DataStorage.start_worker(spider_name, crawl_id)

    Process.link(data_storage_pid)

    # Start RequestsWorker for a given spider
    {:ok, request_storage_pid} =
      Crawly.RequestsStorage.start_worker(spider_name, crawl_id)

    Process.link(request_storage_pid)

    # Add start requests to the requests storage
    init = spider_name.init(options)

    start_requests_from_req = Keyword.get(init, :start_requests, [])

    start_requests_from_urls =
      init
      |> Keyword.get(:start_urls, [])
      |> Crawly.Utils.requests_from_urls()

    start_requests = start_requests_from_req ++ start_requests_from_urls

    # Split start requests, so it's possible to initialize a part of them in async
    # manner
    {start_req, async_start_req} =
      Enum.split(start_requests, @start_request_split_size)

    :ok = store_requests(spider_name, start_req)

    # Start workers
    num_workers =
      Utils.get_settings(:concurrent_requests_per_domain, spider_name, 4)

    worker_pids =
      Enum.map(1..num_workers, fn _x ->
        DynamicSupervisor.start_child(
          spider_name,
          {Crawly.Worker, [spider_name: spider_name, crawl_id: crawl_id]}
        )
      end)

    # Schedule basic service operations for given spider manager
    timeout =
      Utils.get_settings(:manager_operations_timeout, spider_name, @timeout)

    tref = Process.send_after(self(), :operations, timeout)

    Logger.debug(
      "Started #{Enum.count(worker_pids)} workers for #{spider_name}"
    )

    {:ok,
     %{
       name: spider_name,
       crawl_id: crawl_id,
       tref: tref,
       prev_scraped_cnt: 0,
       workers: worker_pids
     }, {:continue, {:startup, {spider_name, async_start_req}}}}
  end

  @impl true
  def handle_continue({:startup, {spider_name, async_start_req}}, state) do
    Task.start(fn ->
      store_requests(spider_name, async_start_req)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:add_workers, num_of_workers}, state) do
    Logger.info("Adding #{num_of_workers} workers for #{state.name}")

    Enum.each(1..num_of_workers, fn _ ->
      DynamicSupervisor.start_child(
        state.name,
        {Crawly.Worker, [spider_name: state.name, crawl_id: state.crawl_id]}
      )
    end)

    {:noreply, state}
  end

  @impl true
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

  defp maybe_stop_spider_by_itemcount_limit(
         spider_name,
         current,
         limit
       )
       when current >= limit do
    Logger.info(
      "Stopping #{inspect(spider_name)}, closespider_itemcount achieved"
    )

    Crawly.Engine.stop_spider(spider_name, :itemcount_limit)
  end

  defp maybe_stop_spider_by_itemcount_limit(_, _, _), do: :ok

  defp maybe_stop_spider_by_timeout(spider_name, current, limit)
       when current <= limit and is_integer(limit) do
    Logger.info("Stopping #{inspect(spider_name)}, itemcount timeout achieved")

    Crawly.Engine.stop_spider(spider_name, :itemcount_timeout)
  end

  defp maybe_stop_spider_by_timeout(_, _, _), do: :ok

  defp maybe_convert_to_integer(value) when is_atom(value), do: value

  defp maybe_convert_to_integer(value) when is_binary(value),
    do: String.to_integer(value)

  defp maybe_convert_to_integer(value) when is_integer(value), do: value

  defp store_requests(spider_name, requests) do
    Enum.each(
      requests,
      fn request ->
        Crawly.RequestsStorage.store(spider_name, request)
      end
    )
  end
end
