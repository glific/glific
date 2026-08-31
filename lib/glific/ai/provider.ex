defmodule Glific.AI.Provider do
  @moduledoc """
  The contract for talking to an AI provider.

  Everything above this behaviour depends on it rather than on a client library,
  so changing library means adding an implementation.

  Implementations must not raise on a provider failure. A timeout, rate limit,
  5xx or rejected model all return `{:error, reason}`, so the caller can record
  a failed message.
  """

  alias Glific.AI.ChatMessage

  @typedoc """
  What one call consumed, as the provider reports it. Cost is the provider's own
  estimate in USD — for observability, not an invoice.
  """
  @type usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cost: number()
        }

  @typedoc """
  Why a call failed.

  The message is deliberately generic: the caller records it against a message
  row and shows it to a user, so it must never carry request detail. What
  actually went wrong is logged and reported to AppSignal by the implementation.
  """
  @type failure ::
          {:not_configured, String.t()}
          | {:provider_error, String.t()}

  @doc """
  Sends a conversation to the provider and returns its reply plus what the call
  consumed.
  """
  @callback generate(messages :: [ChatMessage.t()], opts :: keyword()) ::
              {:ok, ChatMessage.t(), usage()} | {:error, failure()}

  @doc "The module that talks to the provider."
  @spec impl() :: module()
  def impl, do: Glific.AI.Provider.ReqLLM
end
