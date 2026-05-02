defmodule Glific.Tracing do
  @moduledoc """
  OpenTelemetry distributed tracing helpers.

  Provides span creation and W3C traceparent propagation so that an async
  callback (arriving as a new HTTP request / new process) can attach its spans
  as children of the span that originated the outbound call.

  Flow:
    1. Caller creates a root span via `with_span/3`.
    2. Inside that span, `current_traceparent/0` returns a W3C traceparent string
       that is embedded in the outbound request metadata sent to Kaapi.
    3. Kaapi echoes the metadata back in the async callback payload.
    4. The callback handler calls `with_parent/4`, passing the echoed traceparent.
       All spans created inside that block become children of the original span.
  """

  require OpenTelemetry.Tracer

  @doc """
  Runs `fun` inside a new OTel span named `name`.  Returns whatever `fun`
  returns.  `attrs` is a plain map of string/atom keys to scalar values.
  """
  @spec with_span(String.t(), map(), (-> result)) :: result when result: any()
  def with_span(name, attrs \\ %{}, fun) do
    OpenTelemetry.Tracer.with_span name, %{attributes: otel_attrs(attrs)} do
      fun.()
    end
  end

  @doc """
  Returns the W3C `traceparent` string for the currently active span, or `nil`
  when there is no active span.  Store this value in outbound request metadata
  so the async callback can continue the trace.
  """
  @spec current_traceparent() :: String.t() | nil
  def current_traceparent do
    carrier = :otel_propagator_text_map.inject([])

    case :proplists.get_value("traceparent", carrier, nil) do
      nil -> nil
      tp -> tp
    end
  end

  @doc """
  Restores an OTel trace context from a W3C `traceparent` string, then runs
  `fun` inside a new span that becomes a child of the remote span.

  Falls back to a plain root span when `traceparent` is `nil` or cannot be
  parsed.
  """
  @spec with_parent(String.t() | nil, String.t(), map(), (-> result)) :: result
        when result: any()
  def with_parent(nil, name, attrs, fun), do: with_span(name, attrs, fun)

  def with_parent(traceparent, name, attrs, fun) do
    token = :otel_propagator_text_map.extract([{"traceparent", traceparent}])

    try do
      with_span(name, attrs, fun)
    after
      OpenTelemetry.Ctx.detach(token)
    end
  end

  @doc """
  Records a synthetic span whose start time is `start_time_us` (microseconds
  since Unix epoch) and whose end time is now.  The span is ended immediately
  without blocking; its duration reflects elapsed wall-clock time since the
  given timestamp.

  The span is parented under whatever span is active in the current context.
  """
  @spec record_elapsed_span(String.t(), non_neg_integer(), map()) :: :ok
  def record_elapsed_span(name, start_time_us, attrs \\ %{}) when is_integer(start_time_us) do
    # OTel stores start_time as Erlang native monotonic time, not Unix nanoseconds.
    # timestamp_to_nano(T) = convert_time_unit(T + time_offset(), native, nanosecond),
    # so we invert: T = convert_time_unit(unix_ns, nanosecond, native) - time_offset().
    start_time_otel =
      :erlang.convert_time_unit(start_time_us * 1_000, :nanosecond, :native) -
        :erlang.time_offset()

    span =
      OpenTelemetry.Tracer.start_span(name, %{
        start_time: start_time_otel,
        attributes: otel_attrs(attrs)
      })

    OpenTelemetry.Span.end_span(span)
    :ok
  end

  @spec otel_attrs(map()) :: [{String.t(), any()}]
  defp otel_attrs(attrs) do
    Enum.map(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), scalar(v)}
      {k, v} -> {k, scalar(v)}
    end)
  end

  @spec scalar(any()) :: String.t() | number() | boolean()
  defp scalar(v) when is_binary(v) or is_number(v) or is_boolean(v), do: v
  defp scalar(v), do: inspect(v)
end
