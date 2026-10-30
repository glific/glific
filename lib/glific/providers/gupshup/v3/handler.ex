defmodule Glific.Providers.Gupshup.V3.Handler do
  @moduledoc """
  Behaviour for a handler of one type of Gupshup V3 (Meta format) callback change.
  `Glific.Providers.Gupshup.V3.Dispatcher` picks the handler and passes it the
  change's value.
  """

  @doc """
  Handles the value of one change from entry[].changes[] for an organization
  """
  @callback handle(value :: map(), organization_id :: non_neg_integer()) :: :ok
end
