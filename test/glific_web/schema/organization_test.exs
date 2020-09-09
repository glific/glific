defmodule GlificWeb.Schema.OrganizationTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Partners.Organization,
    Partners.Provider,
    Repo,
    Seeds.SeedsDev,
    Settings.Language
  }

  setup do
    provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_users()
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/organizations/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/organizations/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/organizations/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/organizations/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/organizations/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/organizations/delete.gql")
  load_gql(:list_timezones, GlificWeb.Schema, "assets/gql/organizations/list_timezones.gql")

  test "organizations field returns list of organizations" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    organizations = get_in(query_data, [:data, "organizations"])
    assert length(organizations) > 0

    res =
      organizations
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn x -> x == "Glific" end)

    assert res == "Glific"
  end

  test "count returns the number of organizations" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countOrganizations"]) == 1

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"name" => "This organization should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countOrganizations"]) == 0

    {:ok, query_data} = query_gql_by(:count, variables: %{"filter" => %{"name" => "Glific"}})

    assert get_in(query_data, [:data, "countOrganizations"]) == 1
  end

  test "organization id returns one organization or nil", %{user: user} do
    name = "Glific"
    {:ok, organization} = Repo.fetch_by(Organization, %{name: name})

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => organization.id})
    assert {:ok, query_data} = result

    organization = get_in(query_data, [:data, "organization", "organization", "name"])
    assert organization == name

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "organization", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "organization without id returns current user's organization", %{user: user} do
    result = auth_query_gql_by(:by_id, user)
    assert {:ok, query_data} = result

    organization_id = get_in(query_data, [:data, "organization", "organization", "id"])
    assert organization_id == to_string(user.organization_id)
  end

  test "create an organization and test possible scenarios and errors" do
    name = "Organization Test Name"
    shortcode = "org_shortcode"
    email = "test2@glific.org"
    provider_key = "random"
    provider_phone = Integer.to_string(Enum.random(123_456_789..9_876_543_210))

    provider_name = "Default Provider"
    {:ok, provider} = Repo.fetch_by(Provider, %{name: provider_name})

    language_locale = "en_US"
    {:ok, language} = Repo.fetch_by(Language, %{locale: language_locale})

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "name" => name,
            "shortcode" => shortcode,
            "email" => email,
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_phone" => provider_phone,
            "default_language_id" => language.id
          }
        }
      )

    assert {:ok, query_data} = result

    organization = get_in(query_data, [:data, "createOrganization", "organization"])
    assert Map.get(organization, "name") == name
    # check default values
    assert Map.get(organization, "isActive") == true
    assert Map.get(organization, "timezone") == "Asia/Kolkata"

    # try creating the same organization twice
    query_gql_by(:create,
      variables: %{
        "input" => %{
          "name" => "test_name",
          "shortcode" => shortcode,
          "email" => email,
          "provider_key" => provider_key,
          "provider_id" => provider.id,
          "provider_phone" => provider_phone,
          "default_language_id" => language.id
        }
      }
    )

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "name" => "test_name",
            "shortcode" => shortcode,
            "email" => email,
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_phone" => provider_phone,
            "default_language_id" => language.id
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createOrganization", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update an organization and test possible scenarios and errors", %{user: user} do
    organization = Fixtures.organization_fixture()

    name = "Organization Test Name"
    shortcode = "org_shortcode"
    email = "test2@glific.org"
    provider_key = "random"
    provider_phone = Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    timezone = "America/Los_Angeles"

    provider_name = "Default Provider"
    {:ok, provider} = Repo.fetch_by(Provider, %{name: provider_name})

    language_locale = "en_US"
    {:ok, language} = Repo.fetch_by(Language, %{locale: language_locale})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "name" => name,
            "shortcode" => shortcode,
            "email" => email,
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_phone" => provider_phone,
            "default_language_id" => language.id,
            "timezone" => timezone
          }
        }
      )

    assert {:ok, query_data} = result

    updated_organization = get_in(query_data, [:data, "updateOrganization", "organization"])
    assert updated_organization["name"] == name
    assert updated_organization["timezone"] == "America/Los_Angeles"

    # Incorrect timezone should give error
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "timezone" => "incorrent_timezone"
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message == "is invalid"

    # create a temp organization with a new name
    auth_query_gql_by(:create, user,
      variables: %{
        "input" => %{
          "name" => name,
          "shortcode" => "new_shortcode",
          "email" => "new email",
          "provider_key" => provider_key,
          "provider_id" => provider.id,
          "provider_phone" => "new provider_phone",
          "default_language_id" => language.id
        }
      }
    )

    # ensure we cannot update an existing organization with the same shortcode, email or provider_phone
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "name" => "new organization",
            "shortcode" => "new_shortcode",
            "email" => "new email",
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_phone" => "new provider_phone",
            "default_language_id" => language.id
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update an organization with organization settings", %{user: user} do
    {:ok, organization} = Repo.fetch_by(Organization, %{name: "Glific"})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "out_of_office" => %{
              "enabled" => true,
              "enabled_days" => [
                %{
                  "id" => 1,
                  "enabled" => true
                }
              ],
              "start_time" => "T10:00:00",
              "end_time" => "T20:00:00",
              "flow_id" => 1
            }
          }
        }
      )

    assert {:ok, query_data} = result

    out_of_office =
      get_in(query_data, [:data, "updateOrganization", "organization", "out_of_office"])

    assert out_of_office["enabled"] == true
    assert get_in(out_of_office, ["enabled_days", Access.at(0), "enabled"]) == true
    assert get_in(out_of_office, ["enabled_days", Access.at(1), "enabled"]) == false
  end

  test "delete an organization" do
    organization = Fixtures.organization_fixture()

    # sometime This is causing a deadlock issue so we need to fix this
    result = query_gql_by(:delete, variables: %{"id" => organization.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteOrganization", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteOrganization", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "timezones returns list of timezones", %{user: user} do
    result = auth_query_gql_by(:list_timezones, user)
    assert {:ok, query_data} = result

    timezones = get_in(query_data, [:data, "timezones"])
    assert timezones != []
    assert "Asia/Kolkata" in timezones == true
  end
end
