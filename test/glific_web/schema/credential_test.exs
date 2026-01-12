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
    [provider | _] = Glific.Partners.list_providers(%{filter: %{shortcode: "gupshup"}})

    auth_query_gql_by(:create, user,
      variables: %{"input" => %{"shortcode" => provider.shortcode}}
    )

    result =
      auth_query_gql_by(:by_shortcode, user, variables: %{"shortcode" => provider.shortcode})

    assert {:ok, query_data} = result

    credential = get_in(query_data, [:data, "credential", "credential"])
    # this will contain app_name and api_key
    assert credential["secrets"] != "{}"
    assert credential["provider"] == %{"shortcode" => "gupshup"}

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
    assert message =~ "has already been taken"
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

  test "update a gcs credential and and set it to inactive", %{user: user} do
    [provider | _] =
      Glific.Partners.list_providers(%{filter: %{shortcode: "google_cloud_storage"}})

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{"input" => %{"shortcode" => provider.shortcode}}
      )

    credential_id = query_data[:data]["createCredential"]["credential"]["id"]

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => credential_id,
          "input" => %{"is_active" => false}
        }
      )

    assert {:ok, query_data} = result

    assert %{"isActive" => false} = get_in(query_data, [:data, "updateCredential", "credential"])
  end

  test "update a gcs credential and and set it to active with correct creds", %{user: user} do
    Tesla.Mock.mock(fn
      _ -> %Tesla.Env{status: 200}
    end)

    [provider | _] =
      Glific.Partners.list_providers(%{filter: %{shortcode: "google_cloud_storage"}})

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "shortcode" => provider.shortcode,
            "secrets" => Jason.encode!(%{"bucket" => "bucket"})
          }
        }
      )

    credential_id = query_data[:data]["createCredential"]["credential"]["id"]

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => credential_id,
          "input" => %{"is_active" => true}
        }
      )

    assert {:ok, query_data} = result

    assert %{"isActive" => true} = get_in(query_data, [:data, "updateCredential", "credential"])
  end

  test "update a gcs credential and and set it to active, but bucket is missing", %{user: user} do
    Tesla.Mock.mock(fn
      _ -> %Tesla.Env{status: 200}
    end)

    [provider | _] =
      Glific.Partners.list_providers(%{filter: %{shortcode: "google_cloud_storage"}})

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "shortcode" => provider.shortcode,
            "secrets" => Jason.encode!(%{"buckets" => "bucket"})
          }
        }
      )

    credential_id = query_data[:data]["createCredential"]["credential"]["id"]

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => credential_id,
          "input" => %{"is_active" => true}
        }
      )

    assert {:ok, %{errors: [%{message: "Invalid Credentials"}]}} = result
  end

  test "update a gcs credential and and set it to active, error in setting bucket logs", %{
    user: user
  } do
    Tesla.Mock.mock(fn
      _ -> %Tesla.Env{status: 400, body: %{"error" => %{"message" => "something went wrong"}}}
    end)

    [provider | _] =
      Glific.Partners.list_providers(%{filter: %{shortcode: "google_cloud_storage"}})

    {:ok, query_data} =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "shortcode" => provider.shortcode,
            "secrets" => Jason.encode!(%{"bucket" => "bucket"})
          }
        }
      )

    credential_id = query_data[:data]["createCredential"]["credential"]["id"]

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => credential_id,
          "input" => %{"is_active" => true}
        }
      )

    assert {:ok, %{errors: [%{message: "something went wrong"}]}} = result
  end
end
