defmodule Glific.AI.Provider.ReqLLM do
  @moduledoc """
  The `req_llm` implementation of `Glific.AI.Provider`.

  The only module that names `req_llm`, and its types stay inside: callers pass
  and receive `Glific.AI.ChatMessage` and a plain usage map.

  Provider failures are returned, never raised.
  """

  alias Glific.AI.{ChatMessage, Provider, Tool}

  @behaviour Glific.AI.Provider

  @failure_message "The AI provider could not complete the request"

  @default_max_tokens 4_096
  @default_receive_timeout 60_000

  @doc """
  Sends a conversation to the provider.

  Pass `model:` to override the configured default for this call.
  """
  @impl Glific.AI.Provider
  @spec generate([ChatMessage.t()], keyword()) ::
          {:ok, ChatMessage.t(), Glific.AI.Provider.usage()}
          | {:error, Glific.AI.Provider.failure()}
  def generate(messages, opts \\ []) do
    case model(opts) do
      nil -> {:error, {:not_configured, "No model is configured for Glific AI"}}
      spec -> call(spec, messages, opts)
    end
  end

  @doc """

  The model this call resolves to, from `model:` or configuration.

  """
  @impl Glific.AI.Provider
  @spec model(keyword()) :: String.t() | nil
  def model(opts) do
    case opts[:model] do
      override when is_binary(override) and override != "" -> override
      _ -> config()[:model]
    end
  end

  @spec call(String.t(), [ChatMessage.t()], keyword()) ::
          {:ok, ChatMessage.t(), Glific.AI.Provider.usage()}
          | {:error, Glific.AI.Provider.failure()}
  defp call(spec, messages, opts) do
    {tools, opts} = Keyword.pop(opts, :tools, [])

    case ReqLLM.generate_text(
           spec,
           to_provider_chat_messages(messages),
           request_opts(tools, opts)
         ) do
      {:ok, response} ->
        {:ok, reply(response), usage(response)}

      {:error, error} ->
        failed(spec, Glific.SafeLog.safe_inspect(error))
    end
  rescue
    exception ->
      Glific.log_exception(exception)
      {:error, {:provider_error, @failure_message}}
  catch
    :exit, reason ->
      failed(spec, Glific.SafeLog.safe_inspect(reason))
  end

  @spec failed(String.t(), String.t()) :: {:error, Provider.failure()}
  defp failed(spec, detail) do
    Glific.log_error("Glific AI call failed on #{spec}: #{detail}")
    {:error, {:provider_error, @failure_message}}
  end

  # `max_tokens` and `receive_timeout` are req_llm's own option names. The
  # `Glific.AI` config keys are mapped onto them here, inside the adapter.
  @spec request_opts([Tool.spec()], keyword()) :: keyword()
  defp request_opts(tools, opts) do
    [
      max_tokens: config()[:max_tokens] || @default_max_tokens,
      receive_timeout: config()[:receive_timeout] || @default_receive_timeout
    ]
    |> put_configured(:base_url)
    |> put_configured(:api_key)
    |> Keyword.merge(Keyword.delete(opts, :model))
    |> put_tools(tools)
  end

  @spec put_configured(keyword(), atom()) :: keyword()
  defp put_configured(opts, key) do
    case config()[key] do
      nil -> opts
      value -> Keyword.put(opts, key, value)
    end
  end

  @spec put_tools(keyword(), [Tool.spec()]) :: keyword()
  defp put_tools(opts, []), do: opts
  defp put_tools(opts, tools), do: Keyword.put(opts, :tools, Enum.map(tools, &to_req_llm_tool/1))

  @spec to_req_llm_tool(Tool.spec()) :: struct()
  defp to_req_llm_tool(spec) do
    ReqLLM.tool(
      name: spec.name,
      description: spec.description,
      parameter_schema: spec.parameters,
      callback: &refuse_local_execution/1
    )
  end

  @spec refuse_local_execution(map()) :: {:error, String.t()}
  defp refuse_local_execution(_args),
    do: {:error, "tools are executed by Glific.AI.Tools, not by the provider client"}

  @spec config() :: keyword()
  defp config, do: Application.get_env(:glific, Glific.AI, [])

  @doc """
  Converts Glific chat messages into the provider's own format.

  Public so the wire shape can be asserted in tests without calling a provider;
  nothing outside this module should depend on the structs it returns.
  """
  @spec to_provider_chat_messages([ChatMessage.t()]) :: [struct()]
  def to_provider_chat_messages(messages), do: Enum.map(messages, &to_req_llm/1)

  @spec to_req_llm(ChatMessage.t()) :: struct()
  defp to_req_llm(%ChatMessage{role: :system, content: content}),
    do: ReqLLM.Context.system(content || "")

  defp to_req_llm(%ChatMessage{role: :tool} = message),
    do: ReqLLM.Context.tool_result(message.tool_call_id, message.tool_name, message.content || "")

  defp to_req_llm(%ChatMessage{role: :assistant, tool_calls: []} = message),
    do: ReqLLM.Context.assistant(message.content || "")

  defp to_req_llm(%ChatMessage{role: :assistant} = message) do
    ReqLLM.Context.assistant(message.content || "",
      tool_calls: Enum.map(message.tool_calls, &to_req_llm_tool_call/1)
    )
  end

  defp to_req_llm(%ChatMessage{role: :user, content: content}),
    do: ReqLLM.Context.user(content || "")

  @spec to_req_llm_tool_call(ChatMessage.tool_call()) :: map()
  defp to_req_llm_tool_call(%{id: id, name: name, args: args}),
    do: %{id: id, name: name, arguments: args}

  @spec reply(struct()) :: ChatMessage.t()
  defp reply(response) do
    ChatMessage.assistant(
      ReqLLM.Response.text(response) || "",
      response |> ReqLLM.Response.tool_calls() |> Enum.map(&tool_call/1)
    )
  end

  @spec tool_call(ReqLLM.ToolCall.t()) :: ChatMessage.tool_call()
  defp tool_call(%ReqLLM.ToolCall{id: id, function: %{name: name, arguments: arguments}}),
    do: %{id: id, name: name, args: arguments(arguments)}

  @spec arguments(term()) :: map()
  defp arguments(args) when is_map(args), do: args

  defp arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp arguments(_), do: %{}

  @spec usage(struct()) :: Glific.AI.Provider.usage()
  defp usage(response) do
    usage = ReqLLM.Response.usage(response) || %{}

    %{
      input_tokens: Map.get(usage, :input_tokens) || 0,
      output_tokens: Map.get(usage, :output_tokens) || 0,
      cost: Map.get(usage, :total_cost) || 0
    }
  end
end
