defmodule Glific.TicketsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.Tickets` context.
  """

  alias Glific.{
    Fixtures,
    Tickets.Ticket
  }

  @doc """
  Generate a ticket.
  """
  @spec ticket_fixture(map()) :: Ticket.t()
  def ticket_fixture(attrs \\ %{}) do
    user = Fixtures.user_fixture()
    contact = Fixtures.contact_fixture()

    {:ok, ticket} =
      attrs
      |> Enum.into(%{
        body: "some body",
        topic: "some topic",
        organization_id: Fixtures.get_org_id(),
        contact_id: contact.id,
        status: "open",
        user_id: user.id
      })
      |> Glific.Tickets.create_ticket()

    ticket
  end
end
