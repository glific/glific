defmodule GlificWeb.Schema.CredentialTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_users()
    :ok
  end

  load_gql(:by_shortcode, GlificWeb.Schema, "assets/gql/credentials/by_shortcode.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/credentials/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/credentials/update.gql")

  test "credential by shortcode returns one credential or nil", %{user: user} do
    [provider | _] = Glific.Partners.list_providers(%{filter: %{shortcode: "glifproxy"}})

    auth_query_gql_by(:create, user, variables: %{"input" => %{"shortcode" => provider.shortcode}})

    result =
      auth_query_gql_by(:by_shortcode, user, variables: %{"shortcode" => provider.shortcode})

    assert {:ok, query_data} = result

    credential = get_in(query_data, [:data, "credential", "credential"])
    assert credential["secrets"] == "{}"
    assert credential["provider"] == %{"shortcode" => "glifproxy"}

    result =
      auth_query_gql_by(:by_shortcode, user, variables: %{"shortcode" => "wrong shortcode"})

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "credential", "errors", Access.at(0), "message"])
    assert message == "Invalid provider shortcode."
  end

  test "create a credential and test possible scenarios and errors", %{user: user} do
    [provider | _] = Glific.Partners.list_providers(%{filter: %{shortcode: "bigquery"}})

    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"shortcode" => provider.shortcode}}
      )

    assert {:ok, query_data} = result
    assert query_data[:data]["createCredential"]["errors"] == nil
    # check default values
    assert query_data[:data]["createCredential"]["credential"]["keys"] == "{}"
    assert query_data[:data]["createCredential"]["credential"]["isActive"] == false

    # try creating the same credential twice
    result =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"shortcode" => provider.shortcode}}
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createCredential", "errors", Access.at(0), "message"])
    assert query_data[:data]["createCredential"]["errors"] != nil
    assert message == "has already been taken"
  end

  test "update a credential and test possible scenarios and errors", %{user: user} do
    [provider | _] = Glific.Partners.list_providers(%{filter: %{shortcode: "bigquery"}})

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"shortcode" => provider.shortcode}}
      )

    credential_id = query_data[:data]["createCredential"]["credential"]["id"]

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => credential_id,
          "input" => %{"secrets" => "{}"}
        }
      )

    assert {:ok, query_data} = result

    secrets = get_in(query_data, [:data, "updateCredential", "credential", "secrets"])
    assert secrets == "{}"
  end
end
