defmodule Glific.Appsignal do
  @moduledoc """
  A simple interface that connect Oban job status to Appsignal
  """

  @tracer Appsignal.Tracer
  @span Appsignal.Span

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:oban, action, event], measurement, meta, _)
      when event in [:stop, :exception] do
    time = :os.system_time()
    span = record_event(action, measurement, meta, time)

    if event == :exception && meta.attempt >= meta.max_attempts do
      error = inspect(meta.error)
      @span.add_error(span, meta.kind, error, meta.stacktrace)
    end

    @tracer.close_span(span, end_time: time)
  end

  def handle_event(_, _, _, _), do: nil

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

  defp record_event(:plugin, measurement, meta, time) do
    metadata = %{"plugin" => meta.plugin}

    "oban_plugin"
    |> @tracer.create_span(@tracer.current_span(), start_time: time - measurement.duration)
    |> @span.set_name("Oban #{meta.plugin}")
    |> @span.set_attribute("appsignal:category", "oban.plugin")
    |> @span.set_sample_data("meta.data", metadata)
  end

  defp record_event(_, _measurement, _meta, _time), do: nil
end
