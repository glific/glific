defmodule Glific.Clients.Balajanaagraha do
  @moduledoc """
  Custom webhook implementation specific to balajanaagraha usecase
  """

  import Ecto.Query, warn: false

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook(_, _fields),
    do: %{}
end
