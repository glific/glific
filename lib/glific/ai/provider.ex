defmodule Glific.AI.Provider do
  @moduledoc """
  The contract for talking to an AI provider.

  Everything above this behaviour depends on it rather than on a client library,
  so changing library means adding an implementation.

  Implementations must not raise on a provider failure. A timeout, rate limit,
  5xx or rejected model all return `{:error, reason}`, so the caller can record
  a failed message.
  """

  alias Glific.AI.{ChatMessage, Usage}

  @type failure ::
          {:not_configured, String.t()}
          | {:provider_error, String.t()}

  @doc """
  Sends a conversation to the provider and returns its reply plus what the call
  consumed.

  `opts` may carry `:tools`, a list of `Glific.AI.Tool` modules the model is
  allowed to ask for. Implementations describe those tools to the provider but
  never execute them: running a tool goes through `Glific.AI.Tools.run/3`, which
  is where authorisation and read-only enforcement live.
  """
  @callback generate(messages :: [ChatMessage.t()], opts :: keyword()) ::
              {:ok, ChatMessage.t(), Usage.t()} | {:error, failure()}

  @doc "The configured implementation."
  @spec impl() :: module()
  def impl do
    Application.get_env(:glific, Glific.AI, [])
    |> Keyword.get(:provider, Glific.AI.Provider.ReqLLM)
  end
end
