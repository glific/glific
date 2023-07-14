defmodule Glific.Clients.QuestAlliance do
  @moduledoc """
  Custom webhook implementation specific to QuestAlliance
  """
  alias Glific.{
    Clients.CommonWebhook,
    Contacts
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("reset_contact_fields", fields) do
    {:ok, _} =
      get_in(fields, ["contact", "id"])
      |> Glific.parse_maybe_integer!()
      |> Contacts.get_contact!()
      |> Contacts.update_contact(%{fields: %{}})

    fields
  end

  def webhook("jugalbandi", fields), do: CommonWebhook.webhook("jugalbandi", fields)

  def webhook(_, _fields),
    do: %{}
end
