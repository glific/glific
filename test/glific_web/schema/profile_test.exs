defmodule GlificWeb.Schema.ProfileTest do
  @moduledoc """
  Graphql test for profile
  """
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts.Contact,
    Fixtures,
    Profiles.Profile,
    Repo,
    Seeds.SeedsDev
  }

  load_gql(:create, GlificWeb.Schema, "assets/gql/profiles/create_profile.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/profiles/delete_profile.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/profiles/update_profile.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/profiles/by_id.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/profiles/list.gql")
  load_gql(:channels, GlificWeb.Schema, "assets/gql/profiles/channels.gql")

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
    assert fetched_profile["contact"]["id"] == "1"
    assert fetched_profile["contact"]["language"]["label"] == "English"

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
      "language_id" => contact.language_id
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

    # returns the is_active and is_default fields

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"contact_id" => contact.id}
        }
      )

    assert {:ok, query_data} = result

    [profile | _] = get_in(query_data, [:data, "profiles"])
    assert profile["is_active"] == true
    assert profile["is_default"] == false

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

    # Only returns active profiles
    Fixtures.profile_fixture(%{
      "name" => "john",
      "type" => "admin",
      "is_active" => false,
      "organization_id" => 1
    })

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"organization_id" => 1, "is_active" => true}
        }
      )

    assert {:ok, query_data} = result
    assert length(get_in(query_data, [:data, "profiles"])) == 1

    # Test that listing without is_active filter returns all profiles
    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"organization_id" => 1}
        }
      )

    assert {:ok, query_data} = result
    profiles = get_in(query_data, [:data, "profiles"])
    assert length(profiles) == 2

    result =
      auth_query_gql_by(:list, user,
        variables: %{
          "filter" => %{"organization_id" => 1}
        }
      )

    assert {:ok, query_data} = result
    profiles = get_in(query_data, [:data, "profiles"])
    assert length(profiles) == 2
    assert Enum.any?(profiles, &(&1["name"] == "john"))
    assert Enum.any?(profiles, &(&1["name"] == "user"))
  end

  test "each profile shows only the activity from while it was active", %{staff: user} do
    contact = Fixtures.contact_fixture(%{organization_id: user.organization_id})

    profile_attrs = fn name ->
      %{
        "contact_id" => contact.id,
        "organization_id" => contact.organization_id,
        "name" => name,
        "type" => "student",
        "language_id" => 1
      }
    end

    {:ok, active} = Glific.Profiles.create_profile(profile_attrs.("Active"))
    {:ok, never_active} = Glific.Profiles.create_profile(profile_attrs.("Never active"))

    # The message insert trigger stamps the contact's active profile on the message.
    {:ok, contact} = Glific.Contacts.update_contact(contact, %{active_profile_id: active.id})

    Fixtures.message_fixture(%{
      sender_id: contact.id,
      receiver_id: contact.id,
      flow: :inbound,
      organization_id: contact.organization_id
    })

    result =
      auth_query_gql_by(:channels, user, variables: %{"filter" => %{"contact_id" => contact.id}})

    assert {:ok, query_data} = result
    profiles = get_in(query_data, [:data, "profiles"])
    by_name = Map.new(profiles, &{&1["name"], &1["channels"]})

    assert [%{"channel" => "WHATSAPP", "lastMessageAt" => last}] = by_name["Active"]
    assert last != nil

    # Same channel list (the contact's), but no activity of its own.
    assert [%{"channel" => "WHATSAPP", "lastMessageAt" => nil}] = by_name["Never active"]
    assert never_active.id != active.id
  end

  test "one profiles list query gives each contact's profiles their own channel activity", %{
    staff: user
  } do
    [first, second] =
      for name <- ["First", "Second"] do
        contact = Fixtures.contact_fixture(%{organization_id: user.organization_id})

        {:ok, profile} =
          Glific.Profiles.create_profile(%{
            "contact_id" => contact.id,
            "organization_id" => contact.organization_id,
            "name" => name,
            "type" => "student",
            "language_id" => 1
          })

        {:ok, contact} = Glific.Contacts.update_contact(contact, %{active_profile_id: profile.id})
        profile
      end

    Fixtures.message_fixture(%{
      sender_id: first.contact_id,
      receiver_id: first.contact_id,
      flow: :inbound,
      organization_id: first.organization_id
    })

    {:ok, query_data} =
      auth_query_gql_by(:channels, user, variables: %{"opts" => %{"limit" => 1000}})

    by_id = Map.new(get_in(query_data, [:data, "profiles"]), &{&1["id"], &1["channels"]})

    assert [%{"channel" => "WHATSAPP", "lastMessageAt" => last}] = by_id[to_string(first.id)]
    assert last != nil
    assert [%{"channel" => "WHATSAPP", "lastMessageAt" => nil}] = by_id[to_string(second.id)]
  end

  test "a user below staff cannot read profile channels" do
    user = Fixtures.user_fixture(%{roles: ["none"]})

    {:ok, query_data} = auth_query_gql_by(:channels, user, variables: %{"filter" => %{}})

    assert [%{message: "Unauthorized"}] = query_data.errors
    assert get_in(query_data, [:data, "profiles"]) == nil
  end
end
