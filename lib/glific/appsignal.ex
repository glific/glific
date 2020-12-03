defmodule Glific.Appsignal do
  @moduledoc """
  A simple interface that connect Oban job status to Appsignal
  """

  @tracer Appsignal.Tracer
  @span Appsignal.Span

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:oban, :job, event], measurement, meta, _)
      when event in [:stop, :exception] do
    span = record_event(measurement, meta)

    if event == :exception && meta.attempt >= meta.max_attempts do
      error = inspect(meta.error)
      @span.add_error(span, meta.kind, error, meta.stacktrace)
    end

    time = :os.system_time()
    @tracer.close_span(span, end_time: time)
  end

  defp record_event(measurement, meta) do
    metadata = %{"id" => meta.id, "queue" => meta.queue, "attempt" => meta.attempt}
    time = :os.system_time()

    "oban_job"
    |> @tracer.create_span(@tracer.current_span(), start_time: time - measurement.duration)
    |> @span.set_name("Oban #{meta.worker}#perform")
    |> @span.set_attribute("appsignal:category", "oban.worker")
    |> @span.set_sample_data("meta.data", metadata)
    |> @span.set_sample_data("meta.args", meta.args)
  end
end
