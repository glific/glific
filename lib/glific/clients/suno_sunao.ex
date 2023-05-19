defmodule Glific.Clients.SunoSunao do
  @moduledoc """
  This module will focus on SunoSunao usecase
  """

  alias Glific.{ASR.GoogleASR, Contacts.Contact, Repo}

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook(_, _fields), do: %{}
end
