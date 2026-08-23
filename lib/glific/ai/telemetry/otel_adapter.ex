defmodule Glific.AI.Telemetry.OTelAdapter do
  @moduledoc """
  `ReqLLM.OpenTelemetry.Adapter` implementation that injects Glific caller context onto every
  AI runtime span and enforces the redaction allow-list before any attribute reaches the OTel
  SDK.

  ## Why an allow-list, not a deny-list

  `req_llm`'s bridge is attached with `content: :none` (see `Glific.AI.Telemetry.attach/0`),
  which is our primary privacy control: by default it never attaches `gen_ai.input.messages`,
  `gen_ai.output.messages`, `gen_ai.system_instructions`, or `gen_ai.tool.definitions` to a span.
  But a default is not a guarantee — it can be flipped by a future config change, and it does not
  cover every attribute source. `req_llm` unconditionally attaches `gen_ai.tool.call.arguments`
  to `gen_ai.execute_tool` child spans for server-side builtin tool calls (e.g. OpenAI's
  `web_search_call`), regardless of the `:content` option — that path is not gated by content
  mode at all.

  `set_attributes/3` and `start_child_span/5` are the two points where `req_llm` hands us the
  attribute map for a span, so both filter through `allowed_attributes/1` before delegating.
  The allow-list only lets through spec metadata: token counts, model/provider identifiers,
  finish reasons, HTTP status, tool names/ids, and our own `glific.*`/`ai.*` context — never a
  key that could carry a prompt, a completion, a tool argument, or a tool result. A deny-list
  would need updating every time `req_llm` or a future Glific change adds an attribute; an
  allow-list fails closed instead — an attribute we haven't reviewed is dropped, not leaked.

  Denied outright, and never added to the allow-list: `gen_ai.input.messages`,
  `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.definitions`,
  `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`.

  ## Why this matters for Glific specifically

  Langfuse Cloud is a hosted third party. `ChatbotDiagnose` and similar skills read
  `contacts`, `contact_histories`, and `message_history` through tools — beneficiary data about
  real people using an NGO's WhatsApp line. Without this filter, a diagnostic run's spans would
  carry that data verbatim to Langfuse's infrastructure the moment content capture were ever
  turned on for a single call. Full prompts and completions already live in `ai_messages` in
  Glific's own Postgres, reachable through the `aiMessages` GraphQL query — nothing here removes
  that visibility, it only keeps it out of the third-party trace.

  The honest cost: a Langfuse trace built from this allow-list shows *that* a tool returned 14
  rows and how long the call took, not which 14 rows. Debugging a wrong or low-quality answer
  still requires pulling the transcript from `ai_messages`, not just reading the trace.

  ## Delegation

  Every callback except `start_span/3`, `set_attributes/3`, and `start_child_span/5` delegates
  unchanged to `ReqLLM.OpenTelemetry.OTelAdapter`, including the optional metrics and
  timed-child-span callbacks — skipping those would make server-side tool sub-spans render as
  siblings of their parent instead of children, losing the call-tree shape Langfuse groups on.
  """

  @behaviour ReqLLM.OpenTelemetry.Adapter

  alias Glific.AI.Telemetry.Context
  alias ReqLLM.OpenTelemetry.OTelAdapter, as: Default

  @allowed_prefixes ~w(
    gen_ai.usage.
    gen_ai.request.
    gen_ai.response.
    gen_ai.operation.
    gen_ai.provider.
    gen_ai.conversation.
    server.
    glific.
    ai.
  )

  @allowed_exact ~w(
    gen_ai.output.type
    gen_ai.tool.name
    gen_ai.tool.call.id
    gen_ai.tool.type
    error.type
    http.response.status_code
    langfuse.observation.cost_details
    langfuse.user.id
    langfuse.session.id
  )

  # required callbacks
  @impl true
  defdelegate available?(), to: Default
  @impl true
  defdelegate add_event(span, name, attributes, config), to: Default
  @impl true
  defdelegate set_status(span, kind, message, config), to: Default
  @impl true
  defdelegate end_span(span, config), to: Default

  # optional callbacks — delegated to preserve metrics and child-span call-tree shape
  @impl true
  defdelegate metrics_available?(), to: Default
  @impl true
  defdelegate record_histogram(record, config), to: Default
  @impl true
  defdelegate end_span_at(span, end_time, config), to: Default

  # Filtered as well as merged: `ReqLLM.Telemetry.OpenTelemetry.request_start/2` folds the
  # request-side content (`gen_ai.input.messages`, `gen_ai.system_instructions`,
  # `gen_ai.tool.definitions`) into the *start* span's attributes, which never pass through
  # `set_attributes/3`. Filtering only there would leave the prompt itself unguarded the moment
  # anyone sets `content: :attributes`.
  @impl true
  @spec start_span(String.t(), map(), keyword()) :: term()
  def start_span(name, attributes, config) do
    Default.start_span(name, merge_context(allowed_attributes(attributes)), config)
  end

  @impl true
  @spec set_attributes(term(), map(), keyword()) :: :ok
  def set_attributes(span, attributes, config) do
    Default.set_attributes(span, allowed_attributes(attributes), config)
  end

  @impl true
  @spec start_child_span(term(), String.t(), map(), map(), keyword()) :: term()
  def start_child_span(parent, name, attributes, opts, config) do
    Default.start_child_span(parent, name, allowed_attributes(attributes), opts, config)
  end

  @doc false
  @spec allowed_attributes(map()) :: map()
  def allowed_attributes(attributes) when is_map(attributes) do
    Map.filter(attributes, fn {key, _value} -> allowed_key?(key) end)
  end

  @doc false
  @spec merge_context(map()) :: map()
  def merge_context(attributes), do: Map.merge(attributes, context_attributes())

  @spec allowed_key?(atom() | String.t()) :: boolean()
  defp allowed_key?(key) do
    key_string = to_string(key)

    key_string in @allowed_exact or
      Enum.any?(@allowed_prefixes, &String.starts_with?(key_string, &1))
  end

  @spec context_attributes() :: map()
  defp context_attributes do
    context = Context.get()

    %{
      "glific.organization_id" => Map.get(context, :organization_id),
      "glific.user_id" => Map.get(context, :user_id),
      "glific.conversation_id" => Map.get(context, :conversation_id),
      "ai.request_id" => Map.get(context, :request_id),
      "ai.skill" => Map.get(context, :skill),
      "ai.step_index" => Map.get(context, :step_index),
      "langfuse.user.id" => Map.get(context, :user_id),
      "langfuse.session.id" => Map.get(context, :conversation_id)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
