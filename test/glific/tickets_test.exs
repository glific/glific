defmodule Glific.TicketsTest do
  use Glific.DataCase

  alias Glific.{
    Fixtures,
    Notifications,
    Tickets
  }

  describe "tickets" do
    alias Glific.Tickets.Ticket

    import Glific.TicketsFixtures

    @invalid_attrs %{body: nil}

    test "list_tickets/0 returns all tickets" do
      ticket = ticket_fixture()
      assert Tickets.list_tickets(%{}) == [ticket]
    end

    test "get_ticket!/1 returns the ticket with given id" do
      ticket = ticket_fixture()
      assert Tickets.get_ticket!(ticket.id) == ticket
    end

    test "create_ticket/1 with valid data creates a ticket", attrs do
      count = Notifications.count_notifications(%{filter: attrs})

      valid_attrs = %{
        body: "some body",
        topic: "some topic",
        status: "open",
        organization_id: 1,
        contact_id: 1
      }

      assert {:ok, %Ticket{} = ticket} = Tickets.create_ticket(valid_attrs)

      updated_count = Notifications.count_notifications(%{filter: attrs})
      assert ticket.body == "some body"
      assert ticket.topic == "some topic"
      assert updated_count == count + 1
    end

    test "create_ticket/1 with invalid data returns error changeset" do
      contact = Fixtures.contact_fixture()

      assert {:error, %Ecto.Changeset{}} =
               @invalid_attrs
               |> Map.put(:contact_id, contact.id)
               |> Tickets.create_ticket()
    end

    test "update_ticket/2 with valid data updates the ticket" do
      ticket = ticket_fixture()

      update_attrs = %{
        body: "some updated body",
        topic: "some updated topic",
        remarks: "closing remarks",
        status: "closed"
      }

      assert {:ok, %Ticket{} = ticket} = Tickets.update_ticket(ticket, update_attrs)
      assert ticket.body == "some updated body"
      assert ticket.topic == "some updated topic"
      assert ticket.remarks == "closing remarks"
      assert ticket.status == "closed"
    end

    test "update_ticket/2 with empty body" do
      ticket = ticket_fixture()
      assert {:ok, _} = Tickets.update_ticket(ticket, @invalid_attrs)
    end

    test "delete_ticket/1 deletes the ticket" do
      ticket = ticket_fixture()
      assert {:ok, %Ticket{}} = Tickets.delete_ticket(ticket)
      assert_raise Ecto.NoResultsError, fn -> Tickets.get_ticket!(ticket.id) end
    end

    test "change_ticket/1 returns a ticket changeset" do
      ticket = ticket_fixture()
      assert %Ecto.Changeset{} = Tickets.change_ticket(ticket)
    end

    test "close multiple tickets and test possible scenarios and errors" do
      _ticket = ticket_fixture()

      {:ok, ticket} =
        Repo.fetch_by(Ticket, %{topic: "some topic", organization_id: 1})

      params = %{
        "topic" => [ticket.topic],
        "status" => "closed"
      }

      {:ok, result_map} = Tickets.update_ticket_status_based_on_topic(params)

      message = result_map |> Map.get(:message)
      assert message == "Updated successfully"
    end
  end
end
