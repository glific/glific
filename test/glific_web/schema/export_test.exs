defmodule GlificWeb.Schema.ExportTest do
  use GlificWeb.ConnCase, async: false
  use Wormwood.GQLCase

  alias Glific.{
    Seeds.SeedsDev
  }

  setup do
    provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_users()

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "success",
              "users" => []
            })
        }
    end)

    :ok
  end

  load_gql(:export_data, GlificWeb.Schema, "assets/gql/export/data.gql")
  load_gql(:export_stats, GlificWeb.Schema, "assets/gql/export/stats.gql")
  load_gql(:export_config, GlificWeb.Schema, "assets/gql/export/config.gql")

  test "export config returns config information from glific", %{user: user} do
    {:ok, user} =
      Glific.Users.update_user(user, %{
        roles: ["glific_admin"],
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:export_config, user)
    IO.inspect(result)
    assert {:ok, data} = result

    assert data != nil

    data = get_in(data, [:data, "organizationExportConfig", "data"]) |> Jason.decode!()

    assert data["providers"] != nil
    assert data["languages"] != nil
  end

  test "export stats returns stats information from glific for an organization", %{user: user} do
    {:ok, user} =
      Glific.Users.update_user(user, %{
        roles: ["glific_admin"],
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:export_stats, user, variables: %{"filter" => %{}})

    assert {:ok, data} = result

    assert data != nil

    data = get_in(data, [:data, "organizationExportStats", "data"]) |> Jason.decode!()

    assert data["contacts"] != nil
    assert data["contacts"] |> length() > 0

    assert data["messages"] != nil
    assert data["messages"] |> length() > 0
  end

  test "export data returns data information from glific for an organization", %{user: user} do
    {:ok, user} =
      Glific.Users.update_user(user, %{
        roles: ["glific_admin"],
        organization_id: user.organization_id
      })

    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -7, :day)

    opts = %{
      "start_time" => start_time |> DateTime.to_string(),
      "end_time" => end_time |> DateTime.to_string()
    }

    result = auth_query_gql_by(:export_data, user, variables: %{"filter" => opts})

    assert {:ok, data} = result

    assert data != nil

    data =
      get_in(data, [:data, "organizationExportData", "data"])
      |> Jason.decode!()
      |> Map.get("data")

    assert data["contacts"] != nil
    assert data["contacts"] |> length() > 0

    assert data["flows"] != nil
    assert data["flows"] |> length() > 0
  end
end
