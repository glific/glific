defmodule GlificWeb.Schema.ProfileTest do
  @moduledoc """
  Graphql test for profile
  """
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{Contacts.Contact, Profiles.Profile, Repo, Seeds.SeedsDev}

  load_gql(:create, GlificWeb.Schema, "assets/gql/profiles/create_profile.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/profiles/delete_profile.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/profiles/update_profile.gql")

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    :ok
  end

  test "create a profile", %{manager: user} do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: user.organization_id})

    params = %{
      "name" => "user",
      "profile_type" => "profile",
      "contact_id" => contact.id,
      "language_id" => contact.language_id,
      "organization_id" => user.organization_id
      # "profile_registration_fields" => {"key": "value"}
    }

    result = auth_query_gql_by(:create, user, variables: %{"input" => params})
    assert {:ok, query_data} = result
    profile = get_in(query_data, [:data, "createProfile", "profile"])
    assert Map.get(profile, "name") == "user"
    assert Map.get(profile, "profile_type") == "profile"
  end

  test "delete a profile", %{manager: user} do
    {:ok, profile} =
      Repo.fetch_by(Profile, %{name: "user", organization_id: user.organization_id})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => profile.id})

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteProfile", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteProfile", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "update a profile", %{staff: user} do
    {:ok, profile} =
      Repo.fetch_by(Profile, %{name: "user", organization_id: user.organization_id})

    name = "another user"
    profile_type = "user profile"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => profile.id,
          "input" => %{"name" => name, "profile_type" => profile_type}
        }
      )

    assert {:ok, query_data} = result

    new_info = get_in(query_data, [:data, "updateProfile", "profile", "name"])
    assert new_info == name
  end
end
