defmodule GlificWeb.Schema.ConsultingHourTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/consulting_hour/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/consulting_hour/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/consulting_hour/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/consulting_hour/delete.gql")

  test "create a consulting hour entry", %{manager: user} do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "participants" => "Adam",
            "organizationId" => 1,
            "organizationName" => "Glific",
            "staff" => "Adelle Cavin",
            "content" => "GCS issue",
            "when" => "2021-03-08T08:22:51Z",
            "duration" => 10,
            "is_billable" => true
          }
        }
      )

    assert {:ok, query_data} = result
    consulting_hour = get_in(query_data, [:data, "createConsultingHour", "consultingHour"])
    assert consulting_hour["participants"] == "Adam"
    assert consulting_hour["content"] == "GCS issue"
    assert consulting_hour["staff"] == "Adelle Cavin"
  end

  test "update a consulting hours", %{manager: user} = attrs do
    consulting_hour = Fixtures.consulting_hour_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => consulting_hour.id,
          "input" => %{"duration" => 20}
        }
      )

    assert {:ok, query_data} = result

    duration = get_in(query_data, [:data, "updateConsultingHour", "consultingHour", "duration"])
    assert duration == 20
  end

  test "delete a consulting hours", %{user: user} = attrs do
    consulting_hour = Fixtures.consulting_hour_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:delete, user,
        variables: %{
          "id" => consulting_hour.id
        }
      )

    assert {:ok, query_data} = result
    content = get_in(query_data, [:data, "deleteConsultingHour", "consultingHour", "content"])
    assert content == consulting_hour.content
  end

  test "get consulting hours and test possible scenarios and errors", %{user: user} = attrs do
    consulting_hour = Fixtures.consulting_hour_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:by_id, user,
        variables: %{
          "id" => consulting_hour.id
        }
      )

    assert {:ok, query_data} = result
    consulting_hours = get_in(query_data, [:data, "consultingHour", "consultingHour"])

    assert consulting_hours["participants"] == consulting_hour.participants
    assert consulting_hours["content"] == consulting_hour.content
    assert consulting_hours["staff"] == consulting_hour.staff

    # testing error message when id is incorrect
    result =
      auth_query_gql_by(:by_id, user,
        variables: %{
          "id" => consulting_hour.id + 1
        }
      )

    assert {:ok, query_data} = result
    [error] = get_in(query_data, [:errors])
    assert error.message == "No consulting hour found with inputted params"
  end
end
