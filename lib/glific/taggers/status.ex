defmodule Glific.Taggers.Status do
  @moduledoc """
  This module will be responsible for all the contact and message status tagging. Like new user and unread
  """
  alias Glific.Messages.Message
  alias Glific.Taggers

  # hardcoding greeting as 5, since this is our testcase
  # need to handle keywords in tags

  @doc false
  @spec get_status_map :: %{String.t() => integer}
  def get_status_map, do: Glific.Tags.status_map()

  def is_new_contact(contact_id), do: Glific.Contacts.is_new_contact(contact_id)

end
