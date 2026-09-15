defmodule Glific.AI.Langfuse do
  @moduledoc """
  Sends a trace of one answered question to Langfuse.

  Built from `glific_ai_events` after the run rather than instrumented inside
  it, which keeps HTTP off the path a person is waiting on and makes a trace
  reproducible: `trace/1` can be called again for any message id, so a Langfuse
  outage costs nothing and history can be backfilled.

  Traces go over OTLP rather than Langfuse's own ingestion API, which is
  deprecated and sunsets in November 2026. Everything is expressed as
  OpenTelemetry GenAI attributes plus Langfuse's `langfuse.*` namespace, so the
  same payload would reach any OTLP collector. Scores are the exception: they
  have no OTLP representation and go to `/api/public/scores`.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    AI.Event,
    AI.Message,
    Repo,
    SafeLog
  }

  @traces_path "/api/public/otel/v1/traces"
  @scores_path "/api/public/scores"
  @realtime {"x-langfuse-ingestion-version", "4"}
  @phone ~r/\b\d{10,15}\b/
  @email ~r/\b[\w.+-]+@[\w-]+\.[\w.]{2,}\b/

  @doc """
  Traces a question in the background.

  Returns immediately, and nothing it does can fail the answer. The keys are
  checked here, once, so a test or a local shell without them never reaches the
  network.
  """
  @spec trace_async(non_neg_integer()) :: :ok
  def trace_async(message_id) do
    if config()[:public_key], do: Task.start(fn -> trace(message_id) end)
    :ok
  end

  @doc """
  Sends a rating someone gave an answer, in the background.
  """
  @spec score_async(Event.t()) :: :ok
  def score_async(%Event{} = event) do
    if config()[:public_key], do: Task.start(fn -> score(event) end)
    :ok
  end

  @doc """
  Builds and sends the trace for one answered question.

  Safe to call again for the same message: the ids are derived from the message
  and its events rather than generated, so Langfuse updates the trace in place.
  """
  @spec trace(non_neg_integer()) :: :ok | {:error, String.t()}
  def trace(message_id) do
    with {:ok, payload} <- payload(message_id), do: post(@traces_path, payload)
  rescue
    exception ->
      Glific.log_exception(exception)
      {:error, Exception.message(exception)}
  end

  @doc """
  Sends the rating recorded on one assistant event.

  Scores are what make it possible to filter traces by whether the answer was
  any good, so a bad answer can be found again and read in full.
  """
  @spec score(Event.t()) :: :ok | {:error, String.t()}
  def score(%Event{data: %{"feedback" => feedback}} = event) do
    with {:ok, message} <- fetch(event.message_id) do
      post(@scores_path, %{
        id: hashed("glific_ai.score.#{event.id}", 16),
        traceId: trace_id(message),
        name: "user-feedback",
        dataType: "CATEGORICAL",
        value: feedback["rating"],
        comment: mask(feedback["content"]),
        environment: environment()
      })
    end
  rescue
    exception ->
      Glific.log_exception(exception)
      {:error, Exception.message(exception)}
  end

  def score(%Event{}), do: :ok

  @doc """
  The OTLP payload for one question.

  Public so the wire shape can be asserted in tests without a Langfuse project;
  nothing outside this module should depend on the maps it returns.
  """
  @spec payload(non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  def payload(message_id) do
    with {:ok, message} <- fetch(message_id) do
      {:ok, message_id |> events() |> spans(message)}
    end
  end

  @doc """
  Redacts direct identifiers from text bound for Langfuse.

  Public so what leaves the platform can be asserted in tests.
  """
  @spec mask(String.t() | nil) :: String.t() | nil
  def mask(nil), do: nil

  def mask(text) when is_binary(text) do
    text
    |> String.replace(@email, "[email]")
    |> String.replace(@phone, "[phone]")
  end

  @spec fetch(non_neg_integer()) :: {:ok, Message.t()} | {:error, String.t()}
  defp fetch(message_id) do
    case Repo.get(Message, message_id, skip_organization_id: true) do
      nil -> {:error, "No Glific AI message with id #{message_id}"}
      message -> {:ok, message}
    end
  end

  @spec events(non_neg_integer()) :: [Event.t()]
  defp events(message_id) do
    Event
    |> where([e], e.message_id == ^message_id)
    |> order_by([e], asc: e.step)
    |> Repo.all(skip_organization_id: true)
  end

  @spec spans([Event.t()], Message.t()) :: map()
  defp spans(events, message) do
    trace_id = trace_id(message)
    root_id = span_id("root", message.id)

    children = Enum.flat_map(events, &child(&1, trace_id, root_id, events, message))
    {started, ended} = window(events, message)

    root = %{
      traceId: trace_id,
      spanId: root_id,
      name: "answer-question",
      kind: 1,
      startTimeUnixNano: nano(started),
      endTimeUnixNano: nano(ended),
      status: status(message),
      attributes:
        attributes([
          {"langfuse.trace.name", "answer-question"},
          {"langfuse.observation.type", "agent"},
          {"langfuse.environment", environment()},
          {"session.id", to_string(message.conversation_id)},
          {"user.id", to_string(message.user_id)},
          {"langfuse.trace.tags", tags(message)},
          {"langfuse.trace.metadata.organization_id", message.organization_id},
          {"langfuse.trace.metadata.skill", message.skill},
          {"langfuse.trace.metadata.status", to_string(message.status)},
          {"langfuse.trace.metadata.error", message.error},
          {"gen_ai.request.model", message.model},
          {"gen_ai.usage.input_tokens", message.input_tokens},
          {"gen_ai.usage.output_tokens", message.output_tokens},
          {"gen_ai.usage.cost", message.cost && Decimal.to_float(message.cost)},
          {"gen_ai.prompt", mask(content(events, :user))},
          {"gen_ai.completion", mask(content(events, :assistant))}
        ])
    }

    envelope([root | children])
  end

  @spec child(Event.t(), String.t(), String.t(), [Event.t()], Message.t()) :: [map()]
  defp child(%Event{type: type}, _trace_id, _root_id, _events, _message)
       when type in [:user, :tool_result],
       do: []

  defp child(%Event{type: :routing} = event, trace_id, root_id, events, message) do
    [
      generation(event, trace_id, root_id, events, message, "classify-intent", %{
        "gen_ai.prompt" => mask(content(events, :user)),
        "gen_ai.completion" => event.content
      })
    ]
  end

  defp child(%Event{type: :assistant} = event, trace_id, root_id, events, message) do
    [
      generation(event, trace_id, root_id, events, message, "generate-answer", %{
        "gen_ai.completion" => mask(event.content)
      })
    ]
  end

  defp child(%Event{type: :tool_call} = event, trace_id, root_id, events, message) do
    turn =
      if usage?(event) do
        [
          generation(event, trace_id, root_id, events, message, "generate-tool-calls", %{
            "gen_ai.completion" => requested(event, events)
          })
        ]
      else
        []
      end

    turn ++ [tool(event, trace_id, root_id, events)]
  end

  defp child(_event, _trace_id, _root_id, _events, _message), do: []

  @spec tool(Event.t(), String.t(), String.t(), [Event.t()]) :: map()
  defp tool(event, trace_id, root_id, events) do
    result =
      Enum.find(events, &(&1.type == :tool_result and &1.tool_call_id == event.tool_call_id))

    %{
      traceId: trace_id,
      spanId: span_id("tool", event.id),
      parentSpanId: root_id,
      name: event.content || "call-tool",
      kind: 1,
      startTimeUnixNano: nano(event.inserted_at),
      endTimeUnixNano: nano((result && result.inserted_at) || event.inserted_at),
      attributes:
        attributes([
          {"langfuse.observation.type", "tool"},
          {"langfuse.environment", environment()},
          {"gen_ai.tool.name", event.content},
          {"langfuse.observation.input", mask(encode(event.data["arguments"]))},
          {"langfuse.observation.output", mask(result && result.data["output"])}
        ])
    }
  end

  @spec generation(Event.t(), String.t(), String.t(), [Event.t()], Message.t(), String.t(), map()) ::
          map()
  defp generation(event, trace_id, root_id, events, message, name, extra) do
    spent = event.data["cost"]

    %{
      traceId: trace_id,
      spanId: span_id(name, event.id),
      parentSpanId: root_id,
      name: name,
      kind: 1,
      startTimeUnixNano: nano(previous_time(event, events, message)),
      endTimeUnixNano: nano(event.inserted_at),
      attributes:
        attributes(
          [
            {"langfuse.observation.type", "generation"},
            {"langfuse.environment", environment()},
            {"gen_ai.request.model", event.data["model"] || message.model},
            {"gen_ai.usage.input_tokens", event.data["input_tokens"]},
            {"gen_ai.usage.output_tokens", event.data["output_tokens"]},
            {"gen_ai.usage.cost", spent && spent / 1}
          ] ++ Enum.to_list(extra)
        )
    }
  end

  @spec requested(Event.t(), [Event.t()]) :: String.t()
  defp requested(event, events) do
    next =
      events
      |> Enum.filter(&(&1.type == :tool_call and &1.step > event.step and usage?(&1)))
      |> Enum.map(& &1.step)
      |> Enum.min(fn -> nil end)

    events
    |> Enum.filter(fn candidate ->
      candidate.type == :tool_call and candidate.step >= event.step and
        (is_nil(next) or candidate.step < next)
    end)
    |> Enum.map_join(", ", & &1.content)
  end

  @spec usage?(Event.t()) :: boolean()
  defp usage?(%Event{data: data}), do: is_map(data) and Map.has_key?(data, "input_tokens")

  @spec previous_time(Event.t(), [Event.t()], Message.t()) :: DateTime.t()
  defp previous_time(event, events, message) do
    events
    |> Enum.filter(&(&1.step < event.step))
    |> List.last()
    |> case do
      nil -> message.inserted_at
      earlier -> earlier.inserted_at
    end
  end

  @spec tags(Message.t()) :: [String.t()]
  defp tags(message),
    do: ["ask-glific", "skill:#{message.skill || "unrouted"}", "org:#{message.organization_id}"]

  @spec envelope([map()]) :: map()
  defp envelope(spans) do
    %{
      resourceSpans: [
        %{
          resource: %{
            attributes:
              attributes([
                {"service.name", "glific"},
                {"deployment.environment.name", environment()}
              ])
          },
          scopeSpans: [%{scope: %{name: "glific.ai"}, spans: spans}]
        }
      ]
    }
  end

  @spec post(String.t(), map()) :: :ok | {:error, String.t()}
  defp post(path, payload) do
    config = config()

    [config[:host], path]
    |> Enum.join()
    |> Req.post(
      json: payload,
      headers: [@realtime],
      auth: {:basic, "#{config[:public_key]}:#{config[:secret_key]}"},
      receive_timeout: config[:receive_timeout] || 10_000,
      retry: :transient
    )
    |> case do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        failed("Langfuse returned #{status} for #{path}: #{SafeLog.safe_inspect(body)}")

      {:error, reason} ->
        failed("Langfuse could not be reached: #{SafeLog.safe_inspect(reason)}")
    end
  end

  @spec failed(String.t()) :: {:error, String.t()}
  defp failed(message) do
    Glific.log_error(message)
    {:error, message}
  end

  @spec content([Event.t()], atom()) :: String.t() | nil
  defp content(events, type) do
    events |> Enum.filter(&(&1.type == type)) |> List.last(%Event{}) |> Map.get(:content)
  end

  @spec window([Event.t()], Message.t()) :: {DateTime.t(), DateTime.t()}
  defp window([], message), do: {message.inserted_at, message.updated_at}
  defp window(events, _message), do: {hd(events).inserted_at, List.last(events).inserted_at}

  @spec status(Message.t()) :: map()
  defp status(%Message{status: :failed} = message),
    do: %{code: 2, message: message.error || "failed"}

  defp status(_message), do: %{code: 1}

  @spec trace_id(Message.t()) :: String.t()
  defp trace_id(message), do: hashed("glific_ai.message.#{message.id}", 16)

  @spec span_id(String.t(), non_neg_integer()) :: String.t()
  defp span_id(kind, id), do: hashed("glific_ai.#{kind}.#{id}", 8)

  @spec hashed(String.t(), pos_integer()) :: String.t()
  defp hashed(seed, bytes) do
    :sha256
    |> :crypto.hash(seed)
    |> binary_part(0, bytes)
    |> Base.encode16(case: :lower)
  end

  @spec nano(DateTime.t()) :: String.t()
  defp nano(at), do: at |> DateTime.to_unix(:nanosecond) |> Integer.to_string()

  @spec encode(map() | nil) :: String.t() | nil
  defp encode(nil), do: nil
  defp encode(arguments), do: Jason.encode!(arguments)

  @spec attributes([{String.t(), term()}]) :: [map()]
  defp attributes(pairs) do
    pairs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> %{key: key, value: value(value)} end)
  end

  @spec value(String.t() | integer() | float() | [String.t()]) :: map()
  defp value(value) when is_integer(value), do: %{intValue: Integer.to_string(value)}
  defp value(value) when is_float(value), do: %{doubleValue: value}
  defp value(value) when is_binary(value), do: %{stringValue: value}
  defp value(value) when is_list(value), do: %{arrayValue: %{values: Enum.map(value, &value/1)}}

  @spec environment() :: String.t()
  defp environment do
    case Application.get_env(:glific, :environment, :dev) do
      :prod -> "production"
      :test -> "test"
      _other -> "development"
    end
  end

  @spec config() :: keyword()
  defp config, do: Application.get_env(:glific, __MODULE__, [])
end
