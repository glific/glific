defmodule Glific.Clients.DigitalGreen do
  @moduledoc """
  Tweak and support some custom logic for a customer DigitalGreen
  """


  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("daily", fields), do: fields
  def webhook(_, _), do: %{}

end
