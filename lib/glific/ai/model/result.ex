defmodule Glific.AI.Model.Result do
  @moduledoc """
  The outcome of one `Glific.AI.Model` call, normalised to Glific's own shape.

  This is **our** struct, not `ReqLLM`'s — everything above `Glific.AI.Model` reads `message`,
  `tool_calls`, `finish_reason`, `usage`, and `context` off this struct instead of reaching into
  a provider response directly. `message` is always the assistant's `ReqLLM.Message`, already
  run through `Glific.AI.Codec.normalize/1` by the adapter that built this result — nothing
  above this layer ever holds a non-canonical message.
  """

  alias ReqLLM.Context
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  @typedoc """
  Token accounting for one call, in Glific's own field names rather than a provider's.

  `cached` counts tokens served from a provider's prompt cache; `cache_creation` counts tokens
  written to it on this call. Both are `0` for a provider or call that did not use caching.
  """
  @type usage :: %{
          prompt: non_neg_integer(),
          completion: non_neg_integer(),
          cached: non_neg_integer(),
          cache_creation: non_neg_integer()
        }

  @type t :: %__MODULE__{
          message: Message.t(),
          tool_calls: [ToolCall.t()],
          finish_reason: atom(),
          usage: usage(),
          context: Context.t()
        }

  @enforce_keys [:message, :tool_calls, :finish_reason, :usage, :context]
  defstruct @enforce_keys

  @doc "An all-zero usage map, for adapters/calls that carry no token accounting."
  @spec zero_usage() :: usage()
  def zero_usage, do: %{prompt: 0, completion: 0, cached: 0, cache_creation: 0}
end
