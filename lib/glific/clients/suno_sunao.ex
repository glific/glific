defmodule Glific.Clients.SunoSunao do
  @moduledoc """
  This module will focus on SunoSunao usecase
  """

  alias Glific.Clients.CommonWebhook

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("speech_to_text", fields), do: CommonWebhook.webhook("speech_to_text", fields)
  def webhook(_, _fields), do: %{}
end
