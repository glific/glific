defmodule Glific.Clients.Balajanaagraha do
  @moduledoc """
  Custom webhook implementation specific to balajanaagraha usecase
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Flows.ContactField
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("save_team_member_details", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact"]["id"])
    contact = Contacts.get_contact!(contact_id)
    {:ok, team_size} = Glific.parse_maybe_integer(fields["team_size"])

    contact
    |> ContactField.do_add_contact_field(
      "team_member_#{team_size}",
      "team_member_#{team_size}",
      fields["details"],
      "string"
    )

    %{updated_details: "team_member_#{team_size}"}
  end

  def webhook(_, _fields),
    do: %{}
end
