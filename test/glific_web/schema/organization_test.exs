defmodule GlificWeb.Schema.OrganizationTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Enums.OrganizationStatus,
    Fixtures,
    Partners,
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
  load_gql(:get_services, GlificWeb.Schema, "assets/gql/organizations/get_services.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/organizations/update.gql")
  load_gql(:update_status, GlificWeb.Schema, "assets/gql/organizations/update_status.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/organizations/delete.gql")
  load_gql(:delete_test, GlificWeb.Schema, "assets/gql/organizations/delete_test.gql")
  load_gql(:get_app_usage, GlificWeb.Schema, "assets/gql/organizations/get_app_usage.gql")

  load_gql(:delete_onboarded, GlificWeb.Schema, "assets/gql/organizations/delete_onboarded.gql")
  load_gql(:attachments, GlificWeb.Schema, "assets/gql/organizations/attachments.gql")
  load_gql(:list_timezones, GlificWeb.Schema, "assets/gql/organizations/list_timezones.gql")

  load_gql(
    :list_organization_status,
    GlificWeb.Schema,
    "assets/gql/organizations/list_organization_status.gql"
  )

  test "organizations field returns list of organizations", %{user: user} do
    {:ok, user} =
      Glific.Users.update_user(user, %{
        roles: ["glific_admin"],
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:list, user)
    assert {:ok, query_data} = result

    organizations = get_in(query_data, [:data, "organizations"])
    assert length(organizations) > 0

    res =
      organizations
      |> get_in([Access.all(), "name"])
      |> Enum.find(fn name -> name == "Glific" end)

    assert res == "Glific"
  end

  test "daily_app_usage/2 returns list of gupshup app usage", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "partnerAppUsageList" => [
                %{
                  "appId" => "test-appID-e991-41c7-9fd7-b3cd58a8aedb",
                  "appName" => "2023TestApp",
                  "authentication" => 0,
                  "cumulativeBill" => 0.089,
                  "currency" => "USD",
                  "date" => "2024-06-03",
                  "discount" => 0.0,
                  "fep" => 0,
                  "ftc" => 4,
                  "gsCap" => 75.0,
                  "gsFees" => 0.064,
                  "incomingMsg" => 27,
                  "internationalAuthentication" => 0,
                  "marketing" => 0,
                  "outgoingMediaMsg" => 0,
                  "outgoingMsg" => 37,
                  "service" => 0,
                  "templateMediaMsg" => 0,
                  "templateMsg" => 0,
                  "totalFees" => 0.064,
                  "totalMsg" => 64,
                  "utility" => 0,
                  "waFees" => 0.0
                }
              ]
            })
        }
    end)

    {:ok, query_data} =
      auth_query_gql_by(:get_app_usage, user,
        variables: %{"fromDate" => "2024-06-01", "toDate" => "2024-06-04"}
      )

    app_usage = get_in(query_data, [:data, "dailyAppUsage", Access.at(0)])
    assert app_usage["cumulativeBill"] == 0.089
    assert app_usage["gupshupFees"] == 0.064
    assert app_usage["incomingMsg"] == 27
    assert app_usage["outgoingMsg"] == 37
    assert app_usage["totalFees"] == 0.064
  end

  test "count returns the number of organizations", %{user: user} do
    {:ok, user} =
      Glific.Users.update_user(user, %{
        roles: ["glific_admin"],
        organization_id: user.organization_id
      })

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

  test "staff organization test", %{staff: user} do
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

    provider_name = "Gupshup Enterprise"
    {:ok, bsp_provider} = Repo.fetch_by(Provider, %{name: provider_name})

    language_locale = "en"
    {:ok, language} = Repo.fetch_by(Language, %{locale: language_locale})

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => name,
            "shortcode" => shortcode,
            "email" => email,
            "bsp_id" => bsp_provider.id,
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
    assert Map.get(organization, "sessionLimit") == 60

    # try creating the same organization twice
    auth_query_gql_by(:create, user,
      variables: %{
        "input" => %{
          "name" => "test_name",
          "shortcode" => shortcode,
          "email" => email,
          "bsp_id" => bsp_provider.id,
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
            "bsp_id" => bsp_provider.id,
            "default_language_id" => language.id,
            "active_language_ids" => [language.id]
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "createOrganization", "errors", Access.at(0), "message"])
    assert message =~ "has already been taken"
  end

  test "update an organization status", %{user: user} do
    organization = Fixtures.organization_fixture()

    {:ok, user} =
      Glific.Users.update_user(user, %{
        roles: ["glific_admin"],
        organization_id: user.organization_id
      })

    result =
      auth_query_gql_by(:update_status, user,
        variables: %{
          "updateOrganizationId" => organization.id,
          "status" => "ACTIVE"
        }
      )

    assert {:ok, query_data} = result
    organization = get_in(query_data, [:data, "updateOrganizationStatus", "organization"])
    assert organization["isActive"] == true
    assert organization["isApproved"] == true
    assert organization["name"] == "Fixture Organization"
  end

  test "delete organization inactive organization", %{user: user} do
    organization = Fixtures.organization_fixture(%{is_active: false})

    result =
      auth_query_gql_by(:delete_onboarded, user,
        variables: %{
          "deleteOrganizationId" => organization.id,
          "isConfirmed" => true
        }
      )

    assert {:ok, query_data} = result
    organization = get_in(query_data, [:data, "deleteInactiveOrganization", "organization"])
    assert organization["isActive"] == false
    assert organization["name"] == "Fixture Organization"
  end

  test "updating an organization with a valid phone number will update the main user and contact phone number",
       %{user: user} do
    organization =
      Repo.get!(Glific.Partners.Organization, user.organization_id)

    valid_phone = "917905556238"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "phone" => valid_phone
          }
        }
      )

    assert {:ok, query_data} = result
    updated_organization = get_in(query_data, [:data, "updateOrganization", "organization"])

    {:ok, main_user} =
      Repo.fetch_by(Glific.Users.User, %{contact_id: organization.contact_id})

    {:ok, contact} =
      Repo.fetch_by(Glific.Contacts.Contact, %{id: organization.contact_id})

    refute updated_organization["setting"]["allow_bot_number_update"]
    assert main_user.phone == valid_phone
    assert contact.phone == valid_phone
  end

  test "updating phone fails if NGO Main Account does not exist", %{user: user} do
    organization = Fixtures.organization_fixture()
    valid_phone = "917905556238"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "phone" => valid_phone
          }
        }
      )

    assert {:ok, query_data} = result

    updated_organization = get_in(query_data, [:data, "updateOrganization", "organization"])
    assert updated_organization == nil

    [error] = get_in(query_data, [:errors])
    assert error.message =~ "Organization contact not found"
  end

  test "updating an organization with a completely invalid phone triggers parse error", %{
    user: user
  } do
    organization = Repo.get!(Glific.Partners.Organization, user.organization_id)
    invalid_phone = "abcd"

    {:ok, result} =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{"phone" => invalid_phone}
        }
      )

    assert get_in(result, [:data, "updateOrganization"]) == nil

    errors = get_in(result, [:errors])
    assert [%{message: message}] = errors
    assert message =~ "Phone number is not valid because"
  end

  test "updating an organization with improperly formatted phone returns validation error", %{
    user: user
  } do
    organization = Repo.get!(Glific.Partners.Organization, user.organization_id)
    invalid_phone = "123abc"

    {:ok, result} =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{"phone" => invalid_phone}
        }
      )

    assert get_in(result, [:data, "updateOrganization"]) == nil
    errors = get_in(result, [:errors])
    assert [%{message: message}] = errors
    assert message =~ "Phone number is not valid"
  end

  test "Updating an Organization with Invalid Phone Number does not update NGO Main Account number and Contact phone number",
       %{user: user} do
    organization =
      Repo.get!(Glific.Partners.Organization, user.organization_id)

    invalid_phone = "12345"

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "phone" => invalid_phone
          }
        }
      )

    assert {:ok, query_data} = result
    updated_org = get_in(query_data, [:data, "updateOrganization", "organization"])
    assert updated_org == nil

    {:ok, main_user} =
      Repo.fetch_by(Glific.Users.User, %{contact_id: organization.contact_id})

    {:ok, contact} =
      Repo.fetch_by(Glific.Contacts.Contact, %{id: organization.contact_id})

    assert main_user.phone != invalid_phone
    assert contact.phone != invalid_phone
  end

  test "update an organization and test possible scenarios and errors", %{user: user} do
    name = "Organization Test Name"
    shortcode = "org_shortcode"
    email = "test2@glific.org"
    timezone = "America/Los_Angeles"
    organization = Fixtures.organization_fixture()

    provider_name = "Gupshup Enterprise"
    {:ok, bsp_provider} = Repo.fetch_by(Provider, %{name: provider_name})

    language_locale = "en"
    {:ok, language} = Repo.fetch_by(Language, %{locale: language_locale})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "name" => name,
            "shortcode" => shortcode,
            "email" => email,
            # "bsp_id" => bsp_provider.id,
            "default_language_id" => language.id,
            "active_language_ids" => [language.id],
            "timezone" => timezone,
            "sessionLimit" => 180
          }
        }
      )

    assert {:ok, query_data} = result

    updated_organization = get_in(query_data, [:data, "updateOrganization", "organization"])
    assert updated_organization["name"] == name
    assert updated_organization["timezone"] == "America/Los_Angeles"
    assert updated_organization["sessionLimit"] == 180

    # Incorrect timezone should give error
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "timezone" => "incorrect_timezone"
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message =~ "is invalid"

    # create a temp organization with a new name
    auth_query_gql_by(:create, user,
      variables: %{
        "input" => %{
          "name" => name,
          "shortcode" => "new_shortcode",
          "email" => "new email",
          "bsp_id" => bsp_provider.id,
          "default_language_id" => language.id,
          "active_language_ids" => [language.id]
        }
      }
    )

    # ensure we cannot update an existing organization with the same shortcode, email
    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "name" => "new organization",
            "shortcode" => "new_shortcode",
            "email" => "new email"
          }
        }
      )

    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])
    assert message =~ "has already been taken"

    # update organization fields with valid param
    fields = %{"organization_name" => "Glific", "url" => "/registration"} |> Jason.encode!()

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => organization.id,
          "input" => %{
            "fields" => fields
          }
        }
      )

    assert {:ok, query_data} = result
    updated_organization = get_in(query_data, [:data, "updateOrganization", "organization"])

    assert updated_organization["fields"] ==
             "{\"url\":\"/registration\",\"organization_name\":\"Glific\"}"
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

    message_1 =
      get_in(query_data, [:data, "updateOrganization", "errors", Access.at(0), "message"])

    message_2 =
      get_in(query_data, [:data, "updateOrganization", "errors", Access.at(1), "message"])

    assert message_1 =~ "has an invalid entry" || message_2 =~ "has an invalid entry"

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
    assert message =~ "default language must be updated according to active languages"
  end

  @default_goth_json """
  {
  "project_id": "DEFAULT PROJECT ID",
  "private_key_id": "DEFAULT API KEY",
  "client_email": "DEFAULT CLIENT EMAIL",
  "private_key": "DEFAULT PRIVATE KEY"
  }
  """

  test "get an organization services", %{user: user} = attrs do
    Fixtures.organization_fixture()
    result = auth_query_gql_by(:get_services, user)
    assert {:ok, query_data} = result
    services = get_in(query_data, [:data, "organizationServices"])
    assert services["fun_with_flags"] == true
    assert services["bigquery"] == false
    assert services["google_cloud_storage"] == false

    # should create credentials and update organization services

    valid_attrs = %{
      secrets: %{"service_account" => @default_goth_json},
      is_active: true,
      shortcode: "bigquery",
      organization_id: attrs.organization_id
    }

    {:ok, _credential} = Partners.create_credential(valid_attrs)
    result = auth_query_gql_by(:get_services, user)
    assert {:ok, query_data} = result
    services = get_in(query_data, [:data, "organizationServices"])
    assert services["fun_with_flags"] == true
    assert services["bigquery"] == true
    assert services["google_cloud_storage"] == false
    assert services["ticketing_enabled"] == false
    assert services["roles_and_permission"] == false
    assert services["flow_uuid_display"] == false
    assert services["contact_profile_enabled"] == false
    assert services["auto_translation_enabled"] == false
    assert services["whatsapp_group_enabled"] == false
    assert services["whatsapp_forms_enabled"] == false
    assert services["unified_api_enabled"] == false
    assert services["certificate_enabled"] == false
    assert services["kaapi_enabled"] == false
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

  test "delete an organization queues a background job", %{user: user} do
    organization = Fixtures.organization_fixture(%{status: :ready_to_delete})

    result = auth_query_gql_by(:delete, user, variables: %{"id" => organization.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteOrganization", "errors"]) == nil

    # Organization should still exist immediately after mutation
    assert {:ok, _org} = Repo.fetch(Organization, organization.id)

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :purge, with_safety: false)

    # After job completes, organization is soft-deleted (record preserved with deleted_at)
    {:ok, deleted_org} =
      Repo.fetch(Organization, organization.id, skip_organization_id: true)

    assert deleted_org.deleted_at != nil

    result = auth_query_gql_by(:delete, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message = get_in(query_data, [:data, "deleteOrganization", "errors", Access.at(0), "message"])
    assert message == "Resource not found"
  end

  test "delete an organization test data", %{user: user} do
    organization = Fixtures.organization_fixture()

    # sometime This is causing a deadlock issue so we need to fix this
    result = auth_query_gql_by(:delete_test, user, variables: %{"id" => organization.id})
    assert {:ok, query_data} = result

    assert get_in(query_data, [:data, "deleteOrganizationTestData", "errors"]) == nil

    result = auth_query_gql_by(:delete_test, user, variables: %{"id" => 123_456_789})
    assert {:ok, query_data} = result

    message =
      get_in(query_data, [:data, "deleteOrganizationTestData", "errors", Access.at(0), "message"])

    assert message == "Resource not found"
  end

  test "attachments enabled returns false by default, but true when we have GCS credential", %{
    user: user
  } do
    result = auth_query_gql_by(:attachments, user, variables: %{"id" => user.organization_id})
    assert {:ok, query_data} = result

    enabled? = get_in(query_data, [:data, "attachmentsEnabled"])
    assert enabled? == false
  end

  test "timezones returns list of timezones", %{user: user} do
    result = auth_query_gql_by(:list_timezones, user)
    assert {:ok, query_data} = result

    timezones = get_in(query_data, [:data, "timezones"])
    assert timezones != []
    assert "Asia/Kolkata" in timezones == true
  end

  test "organization status returns list of status", %{user: user} do
    result = auth_query_gql_by(:list_organization_status, user)
    assert {:ok, query_data} = result

    statuses = get_in(query_data, [:data, "organizationStatus"])
    assert statuses != []
    assert length(statuses) == length(OrganizationStatus.__enum_map__())
  end
end
