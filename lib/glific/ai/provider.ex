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

  @type failure :: {:provider_error, String.t()}

  @doc "Settings every implementation reads."
  @spec config() :: keyword()
  def config, do: Application.get_env(:glific, Glific.AI, [])

  @doc """
  Sends a conversation to the provider and returns its reply plus what the call
  consumed.
  """
  @callback generate(messages :: [ChatMessage.t()], opts :: keyword()) ::
              {:ok, ChatMessage.t(), usage()} | {:error, failure()}

  @doc """
  The model to use: `opts[:model]` when given, otherwise the configured default.

  The default is a light model; a caller passes `model:` when one question needs
  a stronger one. This is the only place a model is resolved.
  """
  @spec model(keyword()) :: String.t() | nil
  def model(opts \\ []) do
    case opts[:model] do
      override when is_binary(override) and override != "" -> override
      _ -> config()[:model]
    end
  end

  @doc "The module that talks to the provider."
  @spec impl() :: module()
  def impl, do: Glific.AI.Provider.ReqLLM
end
