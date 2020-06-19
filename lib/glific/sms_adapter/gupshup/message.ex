defmodule Glific.SMSAdapter.Gupshup.Message do
  @moduledoc """
   Adapter to send SMS
  """

  @doc """
  Create and send sms
  """
  @spec create(map()) :: {:ok, String.t()}
  def create(request) do
    {:ok, request.code}
  end
end
