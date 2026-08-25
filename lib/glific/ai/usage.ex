defmodule Glific.AI.Usage do
  @moduledoc """
  What one provider call consumed.

  Cost is an estimate the provider catalogue supplies for observability. It is
  not an invoice, and should never be presented to an organisation as a bill.
  """

  @type t() :: %__MODULE__{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cost: Decimal.t()
        }

  defstruct input_tokens: 0, output_tokens: 0, cost: Decimal.new("0")

  @doc """
  Adds two usages together, so a request can accumulate the cost of every call
  it made before writing a single total to `glific_ai_requests`.
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      input_tokens: a.input_tokens + b.input_tokens,
      output_tokens: a.output_tokens + b.output_tokens,
      cost: Decimal.add(a.cost, b.cost)
    }
  end
end
