defmodule GlificWeb.Schema.ProfileTest do
  @moduledoc """
  Graphql test for profile
  """
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts.Contact,
    Profiles.Profile,
    Repo,
    Seeds.SeedsDev
  }

  load_gql(:create, GlificWeb.Schema, "assets/gql/profiles/create_profile.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/profiles/delete_profile.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/profiles/update_profile.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/profiles/by_id.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/profiles/list.gql")

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    :ok
  end

  @doc """
  This test will fetch profile by its id
  """

  test "profile by id returns one contact or nil", %{staff: user} do
    name = "user"
    {:ok, profile} = Repo.fetch_by(Profile, %{name: name, organization_id: user.organization_id})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => profile.id})
    assert {:ok, query_data} = result

    fetched_profile = get_in(query_data, [:data, "profile", "profile"])
    assert fetched_profile["name"] == name

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "profile", "errors", Access.at(0), "message"])
    assert message == "Profile not found or permission denied."
  end

  @doc """
  This test will create a profile with valid data
  """

  test "create a profile", %{manager: user} do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: user.organization_id})

    params = %{
      "name" => "Tom",
      "type" => "student",
      "contact_id" => contact.id,
      "language_id" => contact.language_id,
      "organization_id" => user.organization_id
    }

    result = auth_query_gql_by(:create, user, variables: %{"input" => params})
    assert {:ok, query_data} = result
    profile = get_in(query_data, [:data, "createProfile", "profile"])
    assert Map.get(profile, "name") == "Tom"
    assert Map.get(profile, "type") == "student"
  end

  @doc """
  This test will test a deleting a resource from the profile table
  """

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

  @doc """
  This test will update the existing record
  """

  test "update a profile", %{staff: user} do
    {:ok, profile} =
      Repo.fetch_by(Profile, %{name: "user", organization_id: user.organization_id})

    name = "another user"
    type = "user profile"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => profile.id,
          "input" => %{"name" => name, "type" => type}
        }
      )

    assert {:ok, query_data} = result

    new_info = get_in(query_data, [:data, "updateProfile", "profile", "name"])
    assert new_info == name
  end

  @doc """
   This test will return the filter result
  """

  test "List profiles by filter", %{staff: user} do
    {:ok, contact} =
      Repo.fetch_by(Contact, %{name: "NGO Main Account", organization_id: user.organization_id})

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"contact_id" => contact.id}
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "profiles"])) == 1

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"contact_id" => 99}
        }
      )

    assert {:ok, query_data} = result

    profiles = get_in(query_data, [:data, "profiles"])
    assert profiles == []

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"name" => "user"}
        }
      )

    assert {:ok, query_data} = result

    [profile | _] = get_in(query_data, [:data, "profiles"])
    assert profile["name"] == "user"

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"organization_id" => 1}
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "profiles"])) == 1
  end
end
