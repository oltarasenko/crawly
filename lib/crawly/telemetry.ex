defmodule Crawly.Telemetry do
  @moduledoc """
  Module for telemetry support for Crawly monitoring

  To disable VM metrics, add this to yout config:
  ```elixir
    config :telemetry_poller, :default, false
  ```
  """
  # based on https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#module-metrics
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    []
  end

  defp periodic_measurements do
    [
      # {:process_info,
      #  event: [:my_app, :worker],
      #  name: Rumbl.Worker,
      #  keys: [:message_queue_len, :memory]}
    ]
  end
end
