defmodule Glific.Taggers.Status do
  @moduledoc """
  This module will be responsible for all the contact and message status tagging. Like new contacttagg and unread
  """

  @doc false
  @spec get_status_map :: %{String.t() => integer}
  def get_status_map, do: Glific.Tags.status_map()

  @doc false
  @spec is_new_contact(integer()) :: boolean()
  def is_new_contact(contact_id), do: Glific.Contacts.is_new_contact(contact_id)
end
