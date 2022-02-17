defmodule GlificWeb.Schema.ConsultingHourTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.Fixtures

  load_gql(:by_id, GlificWeb.Schema, "assets/gql/consulting_hour/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/consulting_hour/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/consulting_hour/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/consulting_hour/delete.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/consulting_hour/list.gql")
  load_gql(:count, GlificWeb.Schema, "assets/gql/consulting_hour/count.gql")
  load_gql(:fetch, GlificWeb.Schema, "assets/gql/consulting_hour/fetch.gql")

  test "create a consulting hour entry", %{user: user} = attrs do
    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "participants" => "Adam",
            "clientId" => attrs.organization_id,
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

  test "count returns the number of consulting hours", %{user: user} = attrs do
    _consulting_hour_1 =
      Fixtures.consulting_hour_fixture(%{organization_id: attrs.organization_id})

    _consulting_hour_2 =
      Fixtures.consulting_hour_fixture(%{
        organization_id: attrs.organization_id,
        staff: "Ken Cavin"
      })

    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countConsultingHours"]) > 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{
          "filter" => %{"organization_name" => "test organization"}
        }
      )

    assert get_in(query_data, [:data, "countConsultingHours"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"staff" => "Ken Cavin"}})

    assert get_in(query_data, [:data, "countConsultingHours"]) == 1
  end

  test "fetch consulting hours field returns list of consulting hours", %{user: user} = attrs do
    _consulting_hour_1 =
      Fixtures.consulting_hour_fixture(%{
        organization_id: attrs.organization_id,
        staff: "Jon Cavin",
        participants: "John Doe"
      })

    _consulting_hour_2 =
      Fixtures.consulting_hour_fixture(%{
        organization_id: attrs.organization_id,
        staff: "Ken Cavin",
        is_billable: false
      })

    result =
      auth_query_gql_by(:fetch, user,
        variables: %{
          "filter" => %{
            "client_id" => attrs.organization_id,
            "end_date" => Date.utc_today() |> Date.to_string(),
            "start_date" => Date.utc_today() |> Timex.shift(days: -11) |> Date.to_string()
          }
        }
      )

    assert {:ok, query_data} = result
    consulting_hours = get_in(query_data, [:data, "fetchConsultingHours"])
    assert length(consulting_hours) == 2
  end

  test "consulting hours field returns list of consulting hours", %{user: user} = attrs do
    _consulting_hour_1 =
      Fixtures.consulting_hour_fixture(%{
        organization_id: attrs.organization_id,
        staff: "Jon Cavin",
        participants: "John Doe"
      })

    _consulting_hour_2 =
      Fixtures.consulting_hour_fixture(%{
        organization_id: attrs.organization_id,
        staff: "Ken Cavin",
        is_billable: false
      })

    result = auth_query_gql_by(:list, user, variables: %{"opts" => %{"order" => "ASC"}})

    assert {:ok, query_data} = result
    consulting_hours = get_in(query_data, [:data, "consultingHours"])
    assert length(consulting_hours) > 0
    [consulting_hour | _] = consulting_hours
    assert get_in(consulting_hour, ["staff"]) == "Jon Cavin"

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"isBillable" => false}})

    assert {:ok, query_data} = result
    consulting_hours = get_in(query_data, [:data, "consultingHours"])
    assert length(consulting_hours) > 0
    [consulting_hour | _] = consulting_hours
    assert get_in(consulting_hour, ["staff"]) == "Ken Cavin"

    result = auth_query_gql_by(:list, user, variables: %{"filter" => %{"participants" => "John"}})

    assert {:ok, query_data} = result
    consulting_hours = get_in(query_data, [:data, "consultingHours"])
    assert length(consulting_hours) > 0
    [consulting_hour | _] = consulting_hours
    assert get_in(consulting_hour, ["participants"]) == "John Doe"

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "opts" => %{"limit" => 1, "offset" => 0}
        }
      )

    assert {:ok, query_data} = result
    consulting_hours = get_in(query_data, [:data, "consultingHours"])
    assert length(consulting_hours) == 1
  end

  @valid_org_attrs %{
    name: "Organization Name 1",
    shortcode: "organization_shortcode 1",
    email: "Contact person email 1"
  }
  test "update a consulting hours", %{user: user} = attrs do
    consulting_hour = Fixtures.consulting_hour_fixture(%{organization_id: attrs.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => consulting_hour.id,
          "input" => %{"duration" => 20, "clientId" => attrs.organization_id}
        }
      )

    assert {:ok, query_data} = result

    duration = get_in(query_data, [:data, "updateConsultingHour", "consultingHour", "duration"])
    assert duration == 20

    # updating consulting hours and changing organization
    new_organization = Fixtures.organization_fixture(@valid_org_attrs)

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => consulting_hour.id,
          "input" => %{"duration" => 120, "clientId" => new_organization.organization_id}
        }
      )

    assert {:ok, query_data} = result

    duration = get_in(query_data, [:data, "updateConsultingHour", "consultingHour", "duration"])
    assert duration == 120
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
    [error] = get_in(query_data, [:data, "consultingHour", "errors"])
    assert error["message"] == "Resource not found"
  end
end
