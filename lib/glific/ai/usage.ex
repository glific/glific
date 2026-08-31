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
end
