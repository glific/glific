defmodule Glific.Appsignal do
  @moduledoc """
  A simple interface that connect Oban job status to Appsignal
  """

  @tracer Appsignal.Tracer
  @span Appsignal.Span

  alias Glific.Repo

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:oban, action, :exception], measurement, meta, _) do
    time = :os.system_time()
    span = record_event(action, measurement, meta, time)

    if meta.attempt >= meta.max_attempts do
      error = inspect(meta.error)
      @span.add_error(span, meta.kind, error, meta.stacktrace)
    end

    @tracer.close_span(span, end_time: time)
  end

  def handle_event([:oban, :job, :stop], measurement, meta, _) do
    # sampling only x% of the total jobs processed to reduce cost and noise.
    sampling_rate =
      Application.get_env(:glific, :appsignal_sampling_rate) |> Glific.parse_maybe_integer!()

    if :rand.uniform() < sampling_rate / 100 do
      # oban telemetry measurements are in microseconds
      queue_time_sec = Float.ceil(measurement.queue_time / 1_000_000, 2)

      Appsignal.add_distribution_value("oban_job_latency", queue_time_sec, %{
        queue: meta.queue,
        worker: meta.worker
      })
    end
  end

  def handle_event([:tesla, :request, :stop], measurement, meta, _) do
    # sampling only x% of the total requests processed to reduce cost and noise.
    # The percentage is set as a config value.
    sampling_rate =
      Application.get_env(:glific, :appsignal_sampling_rate) |> Glific.parse_maybe_integer!()

    # sampling rate multiplier for the default sampling rate,
    # For ex for openai api,  sampling_scale is 5. For a default of 10% sampling rate,
    # 50% of openai requests will go to appsignal
    sampling_scale = meta[:sampling_scale] || 1

    request_duration_milliseconds =
      System.convert_time_unit(measurement.duration, :native, :millisecond)

    status = meta.env.status

    if :rand.uniform() < sampling_rate * sampling_scale / 100 do
      cond do
        # Errors like timeout from tesla etc, status will be nil
        is_nil(status) ->
          Appsignal.increment_counter("tesla_request_error_count", 1, %{
            provider: meta[:provider],
            error: meta.error,
            url: meta.env.url,
            method: meta.env.method
          })

        status >= 400 ->
          Appsignal.increment_counter("tesla_request_error_count", 1, %{
            provider: meta[:provider],
            error: status,
            url: meta.env.url,
            method: meta.env.method
          })

        true ->
          Appsignal.add_distribution_value(
            "tesla_request_response",
            request_duration_milliseconds,
            %{
              method: meta.env.method,
              url: meta.env.url,
              provider: meta[:provider]
            }
          )
      end
    end
  end

  def handle_event([:tesla, :request, :exception], measurement, meta, _) do
    time = :os.system_time()
    span = record_tesla_event(measurement, meta, time)

    error = inspect(meta.reason)
    @span.add_error(span, meta.kind, error, meta.stacktrace)

    @tracer.close_span(span, end_time: time)
  end

  def handle_event(_, _, _, _), do: nil

  @doc """
  Sends oban queue size metric to Appsignal
  """
  @spec send_oban_queue_size :: any()
  def send_oban_queue_size do
    get_oban_queue_data()
    |> Enum.each(fn [queue, state, length] ->
      Appsignal.set_gauge("oban_queue_size", length, %{queue: queue, state: state})
    end)
  end

  @spec record_event(atom(), any(), any(), integer()) :: any()
  defp record_event(:job, measurement, meta, time) do
    metadata = %{"id" => meta.id, "queue" => meta.queue, "attempt" => meta.attempt}

    "oban_job"
    |> @tracer.create_span(@tracer.current_span(), start_time: time - measurement.duration)
    |> @span.set_name("Oban #{meta.worker}#perform")
    |> @span.set_attribute("appsignal:category", "oban.worker")
    |> @span.set_sample_data("meta.data", metadata)
    |> @span.set_sample_data("meta.args", meta.args)
  end

  @ignore_plugins [
    Elixir.Oban.Plugins.Stager,
    Elixir.Oban.Plugins.Lifeline,
    Elixir.Oban.Plugins.Pruner,
    Elixir.Oban.Plugins.Reindexer
  ]

  # ignore some internal Oban plugins which execute quite often
  defp record_event(:plugin, _m, %{plugin: plugin}, _t) when plugin in @ignore_plugins,
    do: nil

  defp record_event(:plugin, measurement, meta, time) do
    metadata = %{"plugin" => meta.plugin}

    "oban_plugin"
    |> @tracer.create_span(@tracer.current_span(), start_time: time - measurement.duration)
    |> @span.set_name("Oban #{meta.plugin}")
    |> @span.set_attribute("appsignal:category", "oban.plugin")
    |> @span.set_sample_data("meta.data", metadata)
  end

  defp record_event(_, _measurement, _meta, _time), do: nil

  @doc """
  Use to set namespace to current appsignal process from anywhere.
  """
  @spec set_namespace(String.t()) :: any()
  def set_namespace(namespace) do
    Appsignal.Span.set_namespace(Appsignal.Tracer.root_span(), namespace)
  end

  @spec get_oban_queue_data :: list()
  defp get_oban_queue_data do
    {:ok, %{rows: rows}} =
      """
      SELECT queue, state, count(id)
      from global.oban_jobs
      where state in ('executing', 'available', 'scheduled', 'retryable')
      group by queue, state
      """
      |> Repo.query([], skip_organization_id: true)

    rows
  end

  @spec record_tesla_event(any(), any(), integer()) :: any()
  defp record_tesla_event(measurement, meta, time) do
    metadata = %{method: meta.env.method, url: meta.env.url}

    request_duration_microseconds =
      System.convert_time_unit(measurement.duration, :native, :microsecond)

    host = URI.parse(metadata.url).host

    "tesla_request"
    |> @tracer.create_span(@tracer.current_span(),
      start_time: time - request_duration_microseconds
    )
    |> @span.set_name("Tesla #{metadata.method} #{host}")
    |> @span.set_attribute("appsignal:category", "tesla.request")
  end
end
