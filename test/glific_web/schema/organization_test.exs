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

  load_gql(:count, GlificWeb.Schema, "assets/gql/organizations/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/organizations/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/organizations/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/organizations/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/organizations/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/organizations/delete.gql")
  load_gql(:list_timezones, GlificWeb.Schema, "assets/gql/organizations/list_timezones.gql")

  test "organizations field returns list of organizations", %{user: user} do
    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    organizations = get_in(query_data, [:data, "organizations"])
    assert length(organizations) > 0

    res =
      organizations
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn x -> x == "Glific" end)

    assert res == "Glific"
  end

  # @tag :pending
  test "count returns the number of organizations", %{user: user} do
    {:ok, query_data} = auth_query_gql_by(:count, user)
    assert get_in(query_data, [:data, "countOrganizations"]) == 1

    {:ok, query_data} =
      auth_query_gql_by(:count, user,
        variables: %{"filter" => %{"name" => "This organization should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countOrganizations"]) == 0

    {:ok, query_data} =
      auth_query_gql_by(:count, user, variables: %{"filter" => %{"name" => "Glific"}})

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

  test "create an organization and test possible scenarios and errors", %{user: user} do
    name = "Organization Test Name"
    shortcode = "org_shortcode"
    email = "test2@glific.org"
    provider_appname = "random"
    provider_phone = Integer.to_string(Enum.random(123_456_789..9_876_543_210))

    provider_name = "Default Provider"
    {:ok, bsp_provider} = Repo.fetch_by(Provider, %{name: provider_name})

    language_locale = "en_US"
    {:ok, language} = Repo.fetch_by(Language, %{locale: language_locale})

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => name,
            "shortcode" => shortcode,
            "email" => email,
            "provider_appname" => provider_appname,
            "bsp_id" => bsp_provider.id,
            "provider_phone" => provider_phone,
            "default_language_id" => language.id,
            "active_language_ids" => [language.id]
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
    auth_query_gql_by(:create, user,
      variables: %{
        "input" => %{
          "name" => "test_name",
          "shortcode" => shortcode,
          "email" => email,
          "provider_appname" => provider_appname,
          "bsp_id" => bsp_provider.id,
          "provider_phone" => provider_phone,
          "default_language_id" => language.id,
          "active_language_ids" => [language.id]
        }
      }
    )

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => "test_name",
            "shortcode" => shortcode,
            "email" => email,
            "provider_appname" => provider_appname,
            "bsp_id" => bsp_provider.id,
            "provider_phone" => provider_phone,
            "default_language_id" => language.id,
            "active_language_ids" => [language.id]
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
    provider_appname = "random"
    provider_phone = Integer.to_string(Enum.random(123_456_789..9_876_543_210))
    timezone = "America/Los_Angeles"

    provider_name = "Default Provider"
    {:ok, bsp_provider} = Repo.fetch_by(Provider, %{name: provider_name})

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
            "provider_appname" => provider_appname,
            # "bsp_id" => bsp_provider.id,
            "provider_phone" => provider_phone,
            "default_language_id" => language.id,
            "active_language_ids" => [language.id],
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
          "provider_appname" => provider_appname,
          "bsp_id" => bsp_provider.id,
          "provider_phone" => "new provider_phone",
          "default_language_id" => language.id,
          "active_language_ids" => [language.id]
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
            "provider_appname" => provider_appname,
            "provider_phone" => "new provider_phone"
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update an organization with default language and active languages", %{user: user} do
    organization = Fixtures.organization_fixture()
    language_1 = Fixtures.language_fixture()
    language_2 = Fixtures.language_fixture()

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "default_language_id" => language_1.id,
            "active_language_ids" => [language_1.id, language_2.id]
          }
        }
      )

    assert {:ok, query_data} = result

    updated_organization = get_in(query_data, [:data, "updateOrganization", "organization"])
    assert updated_organization["default_language"]["id"] == "#{language_1.id}"
    active_language_id = get_in(updated_organization, ["active_languages", Access.at(0), "id"])
    assert active_language_id in ["#{language_1.id}", "#{language_2.id}"]

    # active languages should be subset of supported languages
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "active_language_ids" => [99_999]
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message == "has an invalid entry"

    # default language should be included in active language list
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "default_language_id" => language_1.id,
            "active_language_ids" => [language_2.id]
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message == "default language must be updated according to active languages"
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

  test "delete an organization", %{user: user} do
    organization = Fixtures.organization_fixture()

    # sometime This is causing a deadlock issue so we need to fix this
    result = auth_query_gql_by(:delete, user, variables: %{"id" => organization.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteOrganization", "errors"]) == nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
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
