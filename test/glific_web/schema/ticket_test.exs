defmodule GlificWeb.Schema.TicketTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Repo,
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
  load_gql(:bulk_update, GlificWeb.Schema, "assets/gql/tickets/bulk_update.gql")

  test "tickets field returns list of tickets", %{staff: user} do
    TicketsFixtures.ticket_fixture()

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
  end

  test "tickets field returns list of filtered tickets", %{staff: user} do
    TicketsFixtures.ticket_fixture(%{user_id: user.id})
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
  end

  test "create a ticket and test possible scenarios and errors", %{manager: user} = attrs do
    body = "new ticket"
    contact = Fixtures.contact_fixture(attrs)

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{"body" => body, "contact_id" => contact.id}
        }
      )

    assert {:ok, query_data} = result

    ticket_name = get_in(query_data, [:data, "createTicket", "ticket", "body"])
    assert ticket_name == body

    # create message without required attributes
    result = auth_query_gql_by(:create, user, variables: %{"input" => %{}})

    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "createTicket", "errors", Access.at(0), "message"]) =~
             "can't be blank"
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
    TicketsFixtures.ticket_fixture()
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countTickets"]) > 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"status" => "closed"}})

    assert get_in(query_data, [:data, "countTickets"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"status" => "open"}})

    assert get_in(query_data, [:data, "countTickets"]) == 1
  end

  test "fetch support tickets field returns list of support ticket", %{user: user} = attrs do
    _support_ticket_1 =
      TicketsFixtures.ticket_fixture(%{
        organization_id: attrs.organization_id,
        body: "test body01",
        topic: "test topic01"
      })

    _support_ticket_2 =
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
    assert is_binary(support_tickets) == true
  end

  test "update a  multiple ticket and test possible scenarios and errors", %{manager: user} do
    TicketsFixtures.ticket_fixture()

    {:ok, ticket} =
      Repo.fetch_by(Ticket, %{body: "some body", organization_id: user.organization_id})

    result =
      auth_query_gql_by(:bulk_update, user,
        variables: %{
          "id" => ticket.id,
          "input" => %{"status" => "closed"}
        }
      )

    assert {:ok, query_data} = result
    assert "closed" == get_in(query_data, [:data, "updateBulkTicket", "ticket", "status"])
  end
end
