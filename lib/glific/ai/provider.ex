defmodule Glific.AI.Provider do
  @moduledoc """
  The contract for talking to an AI provider.

  One implementation exists — `Glific.AI.Provider.ReqLLM`. The point of the
  behaviour is that it is the only thing the rest of Glific AI depends on, so
  replacing the client library means writing a second implementation rather than
  changing callers or migrating stored data.

  Implementations must never raise on a provider failure: a timeout, a rate
  limit, a 5xx or a rejected model all come back as `{:error, reason}` so the
  caller can record a failed request.
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
