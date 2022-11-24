defmodule Glific.Clients.Oblf do
  @moduledoc """
  Custom webhook implementation specific to OBLF use case
  """

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook(_, _fields),
    do: %{}
end
