defmodule GlificWeb.Schema.OrganizationTest do
  use GlificWeb.ConnCase, async: true
  use Wormwood.GQLCase

  setup do
    lang = Glific.Seeds.seed_language()
    provider = Glific.Seeds.seed_providers()
    contact = Glific.Seeds.seed_contacts()
    Glific.Seeds.seed_organizations(provider, contact, lang)
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/organizations/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/organizations/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/organizations/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/organizations/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/organizations/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/organizations/delete.gql")

  test "organizations field returns list of organizations" do
    result = query_gql_by(:list)
    assert {:ok, query_data} = result

    organizations = get_in(query_data, [:data, "organizations"])
    assert length(organizations) > 0

    res =
      organizations
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn x -> x == "Default Organization" end)

    assert res == "Default Organization"
  end

  test "count returns the number of organizations" do
    {:ok, query_data} = query_gql_by(:count)
    assert get_in(query_data, [:data, "countOrganizations"]) == 2

    {:ok, query_data} =
      query_gql_by(:count,
        variables: %{"filter" => %{"name" => "This organization should never ever exist"}}
      )

    assert get_in(query_data, [:data, "countOrganizations"]) == 0

    {:ok, query_data} =
      query_gql_by(:count, variables: %{"filter" => %{"name" => "Default Organization"}})

    assert get_in(query_data, [:data, "countOrganizations"]) == 1
  end

  test "organization id returns one organization or nil" do
    name = "Default Organization"
    {:ok, organization} = Glific.Repo.fetch_by(Glific.Partners.Organization, %{name: name})

    result = query_gql_by(:by_id, variables: %{"id" => organization.id})
    assert {:ok, query_data} = result

    organization = get_in(query_data, [:data, "organization", "organization", "name"])
    assert organization == name

    result = query_gql_by(:by_id, variables: %{"id" => 123_456})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "organization", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "create an organization and test possible scenarios and errors" do
    name = "Organization Test Name"
    display_name = "Organization Test Name"
    contact_name = "Test"
    email = "test2@glific.org"
    provider_key = "random"
    provider_number = Integer.to_string(Enum.random(123_456_789..9_876_543_210))

    provider_name = "Default Provider"
    {:ok, provider} = Glific.Repo.fetch_by(Glific.Partners.Provider, %{name: provider_name})

    language_locale = "en_US"
    {:ok, language} = Glific.Repo.fetch_by(Glific.Settings.Language, %{locale: language_locale})

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "name" => name,
            "display_name" => display_name,
            "email" => email,
            "contact_name" => contact_name,
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_number" => provider_number,
            "default_language_id" => language.id
          }
        }
      )

    assert {:ok, query_data} = result

    organization = get_in(query_data, [:data, "createOrganization", "organization"])
    assert Map.get(organization, "name") == name

    # try creating the same organization twice
    query_gql_by(:create,
      variables: %{
        "input" => %{
          "name" => "test_name",
          "display_name" => display_name,
          "email" => email,
          "contact_name" => contact_name,
          "provider_key" => provider_key,
          "provider_id" => provider.id,
          "provider_number" => provider_number,
          "default_language_id" => language.id
        }
      }
    )

    result =
      query_gql_by(:create,
        variables: %{
          "input" => %{
            "name" => "test_name",
            "display_name" => display_name,
            "email" => email,
            "contact_name" => contact_name,
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_number" => provider_number,
            "default_language_id" => language.id
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createOrganization", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "update an organization and test possible scenarios and errors" do
    {:ok, organization} =
      Glific.Repo.fetch_by(Glific.Partners.Organization, %{name: "Default Organization"})

    name = "Organization Test Name"
    display_name = "Organization Test Name"
    contact_name = "Test"
    email = "test2@glific.org"
    provider_key = "random"
    provider_number = Integer.to_string(Enum.random(123_456_789..9_876_543_210))

    provider_name = "Default Provider"
    {:ok, provider} = Glific.Repo.fetch_by(Glific.Partners.Provider, %{name: provider_name})

    language_locale = "en_US"
    {:ok, language} = Glific.Repo.fetch_by(Glific.Settings.Language, %{locale: language_locale})

    result =
      query_gql_by(:update,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "name" => name,
            "display_name" => display_name,
            "email" => email,
            "contact_name" => contact_name,
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_number" => provider_number,
            "default_language_id" => language.id
          }
        }
      )

    assert {:ok, query_data} = result

    new_name = get_in(query_data, [:data, "updateOrganization", "organization", "name"])
    assert new_name == name

    # create a temp organization with a new name
    query_gql_by(:create,
      variables: %{
        "input" => %{
          "name" => "new organization",
          "display_name" => display_name,
          "email" => "new email",
          "contact_name" => contact_name,
          "provider_key" => provider_key,
          "provider_id" => provider.id,
          "provider_number" => "new provider_number",
          "default_language_id" => language.id
        }
      }
    )

    # ensure we cannot update an existing organization with the same name, email or provider_number
    result =
      query_gql_by(:update,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "name" => "new organization",
            "display_name" => display_name,
            "email" => "new email",
            "contact_name" => contact_name,
            "provider_key" => provider_key,
            "provider_id" => provider.id,
            "provider_number" => "new provider_number",
            "default_language_id" => language.id
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message == "has already been taken"
  end

  test "delete an organization" do
    {:ok, organization} =
      Glific.Repo.fetch_by(Glific.Partners.Organization, %{name: "Default Organization"})

    result = query_gql_by(:delete, variables: %{"id" => organization.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteOrganization", "errors"]) == nil

    result = query_gql_by(:delete, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteOrganization", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end
end
