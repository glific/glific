defmodule Glific.AI.Provider.ReqLLM do
  @moduledoc """
  The `req_llm` implementation of `Glific.AI.Provider`.

  This is the **only** module in Glific that names `req_llm`. Its types do not
  escape: what goes in and comes out are `Glific.AI.Message` and
  `Glific.AI.Usage` structs. That containment is what makes the library choice
  reversible — replacing it means writing a sibling module, not migrating stored
  conversations or touching any caller.

  Every provider failure is returned, never raised. A timeout, a rate limit, a
  5xx or a model the provider rejects all arrive as `{:error, reason}` so the
  caller records a failed request instead of losing the job to an exception.
  """

  @behaviour Glific.AI.Provider

  require Logger

  alias Glific.AI.{Message, Models, Usage}

  @impl Glific.AI.Provider
  @spec generate([Message.t()], keyword()) ::
          {:ok, Message.t(), Usage.t()} | {:error, Glific.AI.Provider.failure()}
  def generate(messages, opts \\ []) do
    if Models.configured?() do
      call(messages, opts)
    else
      {:error, {:not_configured, "no model is configured for Glific AI"}}
    end
  end

  @spec call([Message.t()], keyword()) ::
          {:ok, Message.t(), Usage.t()} | {:error, Glific.AI.Provider.failure()}
  defp call(messages, opts) do
    {tools, opts} = Keyword.pop(opts, :tools, [])

    Models.spec()
    |> ReqLLM.generate_text(to_provider_messages(messages), request_opts(tools, opts))
    |> case do
      {:ok, response} ->
        {:ok, reply(response), usage(response)}

      {:error, error} ->
        Logger.warning("Glific AI provider call failed: #{describe(error)}")
        {:error, {:provider_error, describe(error)}}
    end
  rescue
    exception ->
      Glific.log_exception(exception)
      {:error, {:provider_error, Exception.message(exception)}}
  end

  @spec request_opts([module()], keyword()) :: keyword()
  defp request_opts([], opts), do: Keyword.merge(Models.opts(), opts)

  defp request_opts(tools, opts) do
    Models.opts()
    |> Keyword.merge(opts)
    |> Keyword.put(:tools, Enum.map(tools, &to_req_llm_tool/1))
  end

  @spec to_req_llm_tool(module()) :: struct()
  defp to_req_llm_tool(tool) do
    ReqLLM.tool(
      name: tool.name(),
      description: tool.description(),
      parameter_schema: tool.parameters(),
      callback: &refuse_local_execution/1
    )
  end

  # req_llm requires a callback, but it must never be the thing that runs a tool:
  # execution goes through Glific.AI.Tools.run/3, which is where authorisation and
  # read-only enforcement live. Reaching this means the loop was bypassed.
  @spec refuse_local_execution(map()) :: {:error, String.t()}
  defp refuse_local_execution(_args),
    do: {:error, "tools are executed by Glific.AI.Tools, not by the provider client"}

  @doc """
  Converts Glific messages into the provider's own format.

  Public so the wire shape can be asserted in tests without calling a provider;
  nothing outside this module should depend on the structs it returns.
  """
  @spec to_provider_messages([Message.t()]) :: [struct()]
  def to_provider_messages(messages), do: Enum.map(messages, &to_req_llm/1)

  @spec to_req_llm(Message.t()) :: struct()
  defp to_req_llm(%Message{role: :system, content: content}),
    do: ReqLLM.Context.system(content || "")

  defp to_req_llm(%Message{role: :tool} = message),
    do: ReqLLM.Context.tool_result(message.tool_call_id, message.tool_name, message.content || "")

  defp to_req_llm(%Message{role: :assistant, tool_calls: []} = message),
    do: ReqLLM.Context.assistant(message.content || "")

  # A turn where the model asked for tools has to go back carrying those calls.
  # Without them the tool results that follow reference a call the provider never
  # saw, and the request is rejected.
  defp to_req_llm(%Message{role: :assistant} = message) do
    %{
      ReqLLM.Context.assistant(message.content || "")
      | tool_calls: Enum.map(message.tool_calls, &to_req_llm_tool_call/1)
    }
  end

  defp to_req_llm(%Message{content: content}), do: ReqLLM.Context.user(content || "")

  @spec to_req_llm_tool_call(Message.tool_call()) :: map()
  defp to_req_llm_tool_call(%{id: id, name: name, args: args}),
    do: %{id: id, name: name, arguments: args}

  @spec reply(struct()) :: Message.t()
  defp reply(response) do
    Message.assistant(
      ReqLLM.Response.text(response),
      response |> ReqLLM.Response.tool_calls() |> Enum.map(&tool_call/1)
    )
  end

  # req_llm types tool calls loosely, and the shape differs by provider, so every
  # variant is normalised here rather than leaking outward.
  @spec tool_call(term()) :: Message.tool_call()
  defp tool_call(%{name: name} = call) do
    %{
      id: id(call),
      name: name,
      args: call |> Map.get(:arguments, Map.get(call, :args, %{})) |> arguments()
    }
  end

  defp tool_call(%{"name" => name} = call) do
    %{
      id: id(call),
      name: name,
      args: call |> Map.get("arguments", Map.get(call, "input", %{})) |> arguments()
    }
  end

  @spec id(map()) :: String.t()
  defp id(call) do
    Map.get(call, :id) || Map.get(call, "id") ||
      get_in(call, [Access.key(:metadata, %{}), :id]) ||
      Ecto.UUID.generate()
  end

  @spec arguments(term()) :: map()
  defp arguments(args) when is_map(args), do: args

  defp arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp arguments(_), do: %{}

  @spec usage(struct()) :: Usage.t()
  defp usage(response) do
    case ReqLLM.Response.usage(response) do
      %{} = usage ->
        %Usage{
          input_tokens: Map.get(usage, :input_tokens, 0) || 0,
          output_tokens: Map.get(usage, :output_tokens, 0) || 0,
          cost: to_decimal(Map.get(usage, :total_cost))
        }

      _ ->
        %Usage{}
    end
  end

  @spec to_decimal(number() | Decimal.t() | nil) :: Decimal.t()
  defp to_decimal(nil), do: Decimal.new("0")
  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  @spec describe(term()) :: String.t()
  defp describe(%{__exception__: true} = error), do: Exception.message(error)
  defp describe(error), do: Glific.SafeLog.safe_inspect(error)
end
