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
  Starts a long-lived span without ending it and sets it as the active span for the
  current process so that any spans created afterwards become its children.

  Serialises the span context to an opaque Base64 token that can be embedded in the
  outbound request metadata.  Kaapi echoes the metadata back in the async callback,
  so the token travels round-trip without any server-side storage.

  Call `finish_e2e_span/1` from the callback handler once all downstream processing
  is complete.  Returns the token string, or `nil` if the span is not sampled.
  """
  @spec begin_e2e_span(String.t(), map()) :: String.t() | nil
  def begin_e2e_span(name, attrs \\ %{}) do
    span_ctx = OpenTelemetry.Tracer.start_span(name, %{attributes: otel_attrs(attrs)})
    OpenTelemetry.Tracer.set_current_span(span_ctx)

    if OpenTelemetry.Span.is_recording(span_ctx) do
      span_ctx |> :erlang.term_to_binary() |> Base.encode64()
    end
  end

  @doc """
  Ends the span previously started with `begin_e2e_span/2`.

  Decodes the opaque token, restores the span context (including the SDK processor
  closure), and ends the span with the current timestamp.  Safe to call from any
  process on the same Erlang node within the same VM session.

  No-ops silently if the token is `nil`, already consumed, or cannot be decoded.
  """
  @spec finish_e2e_span(String.t() | nil) :: :ok
  def finish_e2e_span(nil), do: :ok

  def finish_e2e_span(token) when is_binary(token) do
    try do
      token
      |> Base.decode64!()
      |> :erlang.binary_to_term()
      |> OpenTelemetry.Span.end_span()
    rescue
      _ -> :ok
    end

    :ok
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
