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

  def webhook("add_evidence", fields) do
    {:ok, evidence_counter} = Glific.parse_maybe_integer(fields["evidence_counter"])
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact"]["id"])
    updated_counter = evidence_counter + 1
    contact = Contacts.get_contact!(contact_id)

    contact
    |> ContactField.do_add_contact_field(
      "evidence_#{updated_counter}",
      "evidence_#{updated_counter}",
      fields["evidence"],
      "string"
    )
    |> ContactField.do_add_contact_field(
      "evidence_counter",
      "evidence_counter",
      updated_counter,
      "string"
    )

    %{evidence_number: updated_counter, evidence: fields["evidence"]}
  end

  def webhook(_, _fields),
    do: %{}
end
