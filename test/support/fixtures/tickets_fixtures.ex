defmodule Glific.TicketsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.Tickets` context.
  """
  alias Glific.Tickets.Ticket

  @doc """
  Generate a ticket.
  """
  @spec ticket_fixture(map()) :: Ticket.t()
  def ticket_fixture(attrs \\ %{}) do
    {:ok, ticket} =
      attrs
      |> Enum.into(%{
        body: "some body",
        topic: "some topic",
        organization_id: 1,
        contact_id: 1,
        status: "open"
      })
      |> Glific.Tickets.create_ticket()

    ticket
  end
end
