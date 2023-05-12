defmodule Glific.TicketsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Glific.Tickets` context.
  """

  @doc """
  Generate a ticket.
  """
  def ticket_fixture(attrs \\ %{}) do
    {:ok, ticket} =
      attrs
      |> Enum.into(%{
        body: "some body",
        topic: "some topic",
        organization_id: 1,
        contact_id: 1,
        status: "Open"
      })
      |> Glific.Tickets.create_ticket()

    ticket
  end
end
