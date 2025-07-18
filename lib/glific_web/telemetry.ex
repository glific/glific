defmodule GlificWeb.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 60_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("glific.repo.query.total_time", unit: {:native, :millisecond}),
      summary("glific.repo.query.decode_time", unit: {:native, :millisecond}),
      summary("glific.repo.query.query_time", unit: {:native, :millisecond}),
      summary("glific.repo.query.queue_time", unit: {:native, :millisecond}),
      summary("glific.repo.query.idle_time", unit: {:native, :millisecond}),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),
      counter("glific.flow.start.duration"),
      counter("glific.message.sent.duration"),
      counter("glific.message.received.duration")
    ]
  end

  defp periodic_measurements do
    [
      {Glific.Appsignal, :send_oban_queue_size, []}
    ]
  end
end
