defmodule Glific.Taggers.Status do
  @moduledoc """
  This module will be responsible for all the contact and message status tagging. Like new contact tag and unread
  """

  @doc false
  @spec get_status_map(map()) :: %{String.t() => integer}
  def get_status_map(%{organization_id: _organization_id} = attrs),
    do: Glific.Tags.status_map(attrs)

  @doc false
  @spec new_contact?(Glific.Messages.Message.t()) :: boolean()
  def new_contact?(message), do: message.message_number <= 1
end
