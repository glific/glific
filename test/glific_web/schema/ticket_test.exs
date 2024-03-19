defmodule GlificWeb.Schema.TicketTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Repo,
    Tickets,
    Tickets.Ticket,
    TicketsFixtures
  }

  load_gql(:list, GlificWeb.Schema, "assets/gql/tickets/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/tickets/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/tickets/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/tickets/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/tickets/delete.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/tickets/count.gql")
  load_gql(:fetch, GlificWeb.Schema, "assets/gql/tickets/fetch.gql")
  load_gql(:bulk_update, GlificWeb.Schema, "assets/gql/tickets/bulk_close.gql")

  test "tickets field returns list of tickets", %{staff: user} do
    ticket_struct = TicketsFixtures.ticket_fixture()

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})

    assert {:ok, query_data} = result

    tickets = get_in(query_data, [:data, "tickets"])
    assert length(tickets) > 0

    res =
      tickets
      |> get_in([Access.all(), "body"])
      |> Enum.find(fn body -> body == "some body" end)

    assert res == "some body"

    [ticket | _] = tickets
    assert get_in(ticket, ["id"]) > 0

    Tickets.delete_ticket(ticket_struct)
  end

  test "tickets field returns list of filtered tickets", %{staff: user} do
    ticket_struct = TicketsFixtures.ticket_fixture(%{user_id: user.id})
    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"status" => "open"}})
    assert {:ok, query_data} = result

    tickets = get_in(query_data, [:data, "tickets"])
    assert length(tickets) == 1

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"contact_id" => 1}})
    assert {:ok, query_data} = result

    tickets = get_in(query_data, [:data, "tickets"])
    assert length(tickets) == 1

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"user_id" => user.id}})
    assert {:ok, query_data} = result

    tickets = get_in(query_data, [:data, "tickets"])
    assert length(tickets) == 1

    name_or_phone_or_body_filter = "Adelle Cavin"

    result =
      auth_query_gql_by(:list, user,
        variables: %{"filter" => %{"name_or_phone_or_body" => name_or_phone_or_body_filter}}
      )

    assert {:ok, query_data} = result

    tickets = get_in(query_data, [:data, "tickets"])
    assert length(tickets) == 1
    Tickets.delete_ticket(ticket_struct)
  end

  test "ticket field id returns one ticket or nil", %{staff: user} do
    TicketsFixtures.ticket_fixture()

    {:ok, ticket} =
      Repo.fetch_by(Ticket, %{body: "some body", organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => ticket.id})
    assert {:ok, query_data} = result

    ticket_body = get_in(query_data, [:data, "ticket", "ticket", "body"])
    assert ticket_body == "some body"

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "ticket", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
    Tickets.delete_ticket(ticket)
  end

  test "create a ticket and test possible scenarios and errors", %{manager: user} = attrs do
    contact = Fixtures.contact_fixture(attrs)
    message = Fixtures.message_fixture(%{receiver_id: contact.id})
    body = "new ticket"

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"body" => body, "contact_id" => message.contact_id}
        }
      )

    assert {:ok, query_data} = result

    ticket = get_in(query_data, [:data, "createTicket", "ticket"])
    assert ticket["body"] == body
    assert ticket["messageNumber"] == message.message_number

    Tickets.get_ticket!(ticket["id"])
    |> Tickets.delete_ticket()

    # create message without required attributes
    result = auth_query_gql_by(:create, user, variables: %{"input" => %{}})

    assert {:ok, query_data} = result

    errors = get_in(query_data, [:data, "createTicket", "errors"])

    case errors do
      nil -> assert is_nil(errors)
      _ -> assert Enum.any?(errors, &(&1["message"] =~ "can't be blank"))
    end
  end

  test "update a ticket and test possible scenarios and errors", %{manager: user} do
    TicketsFixtures.ticket_fixture()

    {:ok, ticket} =
      Repo.fetch_by(Ticket, %{body: "some body", organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => ticket.id,
          "input" => %{"status" => "closed"}
        }
      )

    assert {:ok, query_data} = result
    assert "closed" == get_in(query_data, [:data, "updateTicket", "ticket", "status"])
    Tickets.delete_ticket(ticket)
  end

  test "delete a ticket", %{manager: user} do
    TicketsFixtures.ticket_fixture()

    {:ok, ticket} =
      Repo.fetch_by(Ticket, %{body: "some body", organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => ticket.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteTicket", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteTicket", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "count returns the number of tickets", %{staff: user} do
    ticket = TicketsFixtures.ticket_fixture()
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countTickets"]) > 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"status" => "closed"}})

    assert get_in(query_data, [:data, "countTickets"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"status" => "open"}})

    assert get_in(query_data, [:data, "countTickets"]) == 1

    Tickets.delete_ticket(ticket)
  end

  test "fetch support tickets field returns list of support ticket", %{user: user} = attrs do
    support_ticket_1 =
      TicketsFixtures.ticket_fixture(%{
        organization_id: attrs.organization_id,
        body: "test body01",
        topic: "test topic01"
      })

    support_ticket_2 =
      TicketsFixtures.ticket_fixture(%{
        organization_id: attrs.organization_id,
        body: "test body02",
        status: "closed"
      })

    result =
      auth_query_gql_by(:fetch, user,
        variables: %{
          "filter" => %{
            "end_date" => Date.utc_today() |> Date.to_string(),
            "start_date" => Date.utc_today() |> Timex.shift(days: -11) |> Date.to_string()
          }
        }
      )

    assert {:ok, query_data} = result
    support_tickets = get_in(query_data, [:data, "fetchSupportTickets"])
    time = Timex.format!(DateTime.utc_now(), "{YYYY}-{0M}-{0D}")
    [header | tickets] = String.split(support_tickets, "\n")
    assert header == "status,body,inserted_at,topic,opened_by,assigned_to"

    assert tickets == [
             "open,test body01,#{time},test topic01,NGO Main Account,NGO Main Account,",
             "closed,test body02,#{time},some topic,NGO Main Account,NGO Main Account,",
             ""
           ]

    Tickets.delete_ticket(support_ticket_1)
    Tickets.delete_ticket(support_ticket_2)
  end

  test "update a multiple ticket and test possible scenarios and errors", %{manager: user} do
    TicketsFixtures.ticket_fixture()

    {:ok, ticket} =
      Repo.fetch_by(Ticket, %{body: "some body", organization_id: user.organization_id})

    update_params = %{
      "update_ids" => [ticket.id],
      "status" => "closed"
    }

    result = Tickets.update_bulk_ticket(update_params)
    assert result == true
    Tickets.delete_ticket(ticket)
  end

  test "create_ticket/1 correctly sets message_number", %{manager: user} = _attrs do
    message = Fixtures.message_fixture()
    message_number = message.message_number
    body = "new ticket"

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"body" => body, "contact_id" => message.contact_id}
        }
      )

    assert {:ok, query_data} = result
    created_ticket = get_in(query_data, [:data, "createTicket", "ticket"])

    {:ok, ticket} = Repo.fetch(Ticket, created_ticket["id"])

    assert ticket.message_number == message_number
    Tickets.delete_ticket(ticket)
  end

  test "close multiple tickets and test possible scenarios and errors",
       %{manager: user} = _attrs do
    ticket = TicketsFixtures.ticket_fixture()

    result =
      auth_query_gql_by(:bulk_update, user,
        variables: %{
          "topic" => [ticket.topic],
          "input" => %{"status" => "closed"}
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateTicketStatusBasedOnTopic", "message"])

    assert message == "Updated successfully"
    Tickets.delete_ticket(ticket)
  end
end
