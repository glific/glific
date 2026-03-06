defmodule Glific.PartnersTest do
  alias Faker.{Person, Phone}
  use Oban.Pro.Testing, repo: Glific.Repo
  use Glific.DataCase
  import Mock
  import Swoosh.TestAssertions

  alias Glific.{
    Communications.Mailer,
    Fixtures,
    Mails.MailLog,
    Notifications,
    Notifications.Notification,
    Partners,
    Partners.Credential,
    Partners.Provider,
    Providers.Gupshup.PartnerAPI,
    Providers.Maytapi.WAWorker,
    Repo,
    Seeds.SeedsDev
  }

  describe "provider" do
    alias Glific.Partners.Provider

    @valid_attrs %{
      name: "some name",
      shortcode: "shortcode 1",
      keys: %{},
      secrets: %{}
    }
    @valid_attrs_1 %{
      name: "some name 1",
      shortcode: "shortcode 2",
      keys: %{},
      secrets: %{}
    }
    @valid_attrs_2 %{
      name: "some name 2",
      shortcode: "shortcode 3",
      keys: %{},
      secrets: %{}
    }
    @valid_attrs_3 %{
      name: "some name 3",
      shortcode: "shortcode 4",
      keys: %{},
      secrets: %{}
    }
    @update_attrs %{
      name: "some updated name",
      shortcode: "new shortcode 4",
      keys: %{},
      secrets: %{}
    }
    @invalid_attrs %{
      name: nil,
      keys: %{},
      secrets: %{}
    }

    def provider_fixture(attrs \\ %{}) do
      {:ok, provider} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Partners.create_provider()

      provider
    end

    test "list_providers/0 returns all providers" do
      _provider = provider_fixture()
      assert length(Partners.list_providers()) >= 1
    end

    test "list_providers/1 with multiple provider filteres" do
      _provider1 = provider_fixture(@valid_attrs)
      provider1 = provider_fixture(@valid_attrs_1)

      provider_list = Partners.list_providers(%{filter: %{name: provider1.name}})
      assert provider_list == [provider1]

      provider_list = Partners.list_providers()
      assert length(provider_list) >= 2
    end

    test "count_providers/0 returns count of all providers" do
      provider_fixture()
      assert Partners.count_providers() >= 1

      provider_fixture(@valid_attrs_1)
      assert Partners.count_providers() >= 2

      assert Partners.count_providers(%{filter: %{name: "some name 1"}}) == 1
    end

    test "get_provider!/1 returns the provider with given id" do
      provider = provider_fixture()
      assert Partners.get_provider!(provider.id) == provider
    end

    test "create_provider/1 with valid data creates a provider" do
      assert {:ok, %Provider{} = provider} = Partners.create_provider(@valid_attrs)
      assert provider.name == "some name"
      assert provider.shortcode == "shortcode 1"
    end

    test "create_provider/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_provider(@invalid_attrs)
    end

    test "update_provider/2 with valid data updates the provider" do
      provider = provider_fixture()
      assert {:ok, %Provider{} = provider} = Partners.update_provider(provider, @update_attrs)
      assert provider.name == "some updated name"
      assert provider.shortcode == "new shortcode 4"
    end

    test "update_provider/2 with invalid data returns error changeset" do
      provider = provider_fixture()
      assert {:error, %Ecto.Changeset{}} = Partners.update_provider(provider, @invalid_attrs)
      assert provider == Partners.get_provider!(provider.id)
    end

    test "bspbalance/1 for checking bsp balance" do
      org = SeedsDev.seed_organizations()

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              "{\"status\":\"success\",\"walletResponse\":{\"currency\":\"USD\",\"currentBalance\":0.787,\"overDraftLimit\":-20.0}}"
          }

        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: "{\"status\":\"success\"}"
          }
      end)

      {:ok, data} = Partners.get_bsp_balance(org.id)
      assert %{"balance" => 0.787} == data
    end

    test "set business profile" do
      org = SeedsDev.seed_organizations()

      Tesla.Mock.mock(fn
        %{method: :put} ->
          %Tesla.Env{
            status: 202,
            body: "{\"status\":\"success\"}"
          }
      end)

      {:ok, result} = PartnerAPI.set_business_profile(org.id, %{city: "mumbai"})
      assert %{"status" => "success"} == result
    end

    test "enable template messaging for an app" do
      org = SeedsDev.seed_organizations()

      Tesla.Mock.mock(fn
        %{method: :put} ->
          %Tesla.Env{
            status: 202,
            body: "{\"status\":\"success\"}"
          }
      end)

      {:ok, result} = PartnerAPI.enable_template_messaging(org.id)
      assert %{"status" => "success"} == result
    end

    test "test app link using api key" do
      org = SeedsDev.seed_organizations()

      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: "{\"partnerId\":49,\"status\":\"success\"}"
          }
      end)

      {:ok, result} = PartnerAPI.link_gupshup_app(org.id)
      assert %{"partnerId" => 49, "status" => "success"} == result
    end

    test "successfully fetches HSM templates" do
      org = SeedsDev.seed_organizations()

      Tesla.Mock.mock(fn
        %{method: :post, url: "https://partner.gupshup.io/partner/account/login"} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                status: "success",
                data: %{
                  token: "sk_test_partner_token"
                }
              })
          }

        %{method: :get, url: url} ->
          cond do
            String.contains?(url, "/token") ->
              %Tesla.Env{
                status: 200,
                body:
                  Jason.encode!(%{
                    partner_app_token: "sk_test_partner_app_token"
                  })
              }

            String.contains?(url, "/templates") ->
              %Tesla.Env{
                status: 200,
                body:
                  Jason.encode!(%{
                    status: "success",
                    templates: []
                  })
              }

            true ->
              raise "Unexpected GET request to: #{url}"
          end
      end)

      {:ok, response} = PartnerAPI.get_templates(org.id)
      decoded_body = Jason.decode!(response.body)

      assert decoded_body["status"] == "success"
    end

    test "recharge_partner/2 should transfer balance from ISV partner to app" do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: "{\"message\":\"Amount has been transferred successfully\"}"
          }
      end)

      {:ok, result} = PartnerAPI.recharge_partner("9999999999", 100.000)
      assert %{"message" => "Amount has been transferred successfully"} == result
    end

    test "delete_provider/1 deletes the provider" do
      provider = provider_fixture()
      assert {:ok, %Provider{}} = Partners.delete_provider(provider)
      assert_raise Ecto.NoResultsError, fn -> Partners.get_provider!(provider.id) end
    end

    test "ensure that delete_provider/1 with foreign key constraints give error" do
      organization = Fixtures.organization_fixture()
      provider = Partners.get_provider!(organization.bsp_id)
      # check for no assoc constraint on credentials and organizations
      assert {:error, _} = Partners.delete_provider(provider)
    end

    test "change_provider/1 returns a provider changeset" do
      provider = provider_fixture()
      assert %Ecto.Changeset{} = Partners.change_provider(provider)
    end

    test "list_providers/1 with multiple providers" do
      _c0 = provider_fixture(@valid_attrs)
      _c1 = provider_fixture(@valid_attrs_1)
      _c2 = provider_fixture(@valid_attrs_2)
      _c3 = provider_fixture(@valid_attrs_3)

      assert length(Partners.list_providers()) >= 4
    end

    test "ensure that creating providers with same name give an error" do
      provider_fixture(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Partners.create_provider(@valid_attrs)
    end
  end

  describe "organizations" do
    alias Glific.{
      Caches,
      Contacts,
      Fixtures,
      Partners.Organization,
      Settings
    }

    @valid_org_attrs %{
      name: "Organization Name",
      shortcode: "organization_shortcode",
      email: "Contact person email"
    }

    @valid_org_attrs_1 %{
      name: "Organization Name 1",
      shortcode: "organization_shortcode 1",
      email: "Contact person email 1"
    }

    @update_org_attrs %{
      name: "Updated Name",
      shortcode: "updated_shortcode"
    }

    @invalid_org_attrs %{bsp_id: nil, name: nil}

    @valid_default_language_attrs %{
      label: "English",
      label_locale: "English",
      locale: "en",
      is_active: true
    }

    def default_language_fixture(attrs \\ %{}) do
      {:ok, default_language} =
        attrs
        |> Enum.into(@valid_default_language_attrs)
        |> Settings.language_upsert()

      default_language
    end

    @spec contact_fixture() :: Contacts.Contact.t()
    def contact_fixture do
      organization = Fixtures.organization_fixture()

      {:ok, contact} =
        Glific.Contacts.create_contact(%{
          name: Person.name(),
          phone: Phone.EnUs.phone(),
          organization_id: organization.id
        })

      contact
    end

    test "list_organizations/0 returns all organizations" do
      _organization = Fixtures.organization_fixture()
      assert length(Partners.list_organizations()) >= 1
    end

    test "count_organizations/0 returns count of all organizations" do
      Fixtures.organization_fixture()
      assert Partners.count_organizations() >= 1

      Fixtures.organization_fixture(@valid_org_attrs_1)
      assert Partners.count_organizations() >= 2

      assert Partners.count_organizations(%{filter: %{name: "Organization Name 1"}}) == 1
    end

    test "get_organization!/1 returns the organization with given id" do
      organization = Fixtures.organization_fixture()
      assert Partners.get_organization!(organization.id) == organization
    end

    test "create_organization/1 with valid data creates an organization" do
      language = default_language_fixture()

      assert {:ok, %Organization{} = organization} =
               @valid_org_attrs
               |> Map.merge(%{
                 bsp_id: provider_fixture().id,
                 default_language_id: language.id,
                 active_language_ids: [language.id]
               })
               |> Partners.create_organization()

      assert organization.name == @valid_org_attrs.name
      assert organization.shortcode == @valid_org_attrs.shortcode
      assert organization.email == @valid_org_attrs.email
    end

    test "create_organization/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_organization(@invalid_org_attrs)
    end

    test "create_organization/1 should add default values for organization settings" do
      language = default_language_fixture()

      {:ok, %Organization{} = organization} =
        @valid_org_attrs
        |> Map.merge(%{
          bsp_id: provider_fixture().id,
          default_language_id: language.id,
          active_language_ids: [language.id]
        })
        |> Partners.create_organization()

      assert organization.out_of_office.enabled == false
      day1 = get_in(organization.out_of_office.enabled_days, [Access.at(0)])
      assert day1.enabled == false
    end

    test "update_organization/2 with valid data updates the organization" do
      organization = Fixtures.organization_fixture()

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, @update_org_attrs)

      assert organization.name == @update_org_attrs.name
    end

    test "update_organization/2 with invalid data returns error changeset" do
      organization = Fixtures.organization_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Partners.update_organization(organization, @invalid_org_attrs)

      assert organization == Partners.get_organization!(organization.id)
    end

    test "update_organization/2 should validate default language and active languages" do
      organization = Fixtures.organization_fixture()
      another_language = Fixtures.language_fixture()

      assert {:error, _} =
               Partners.update_organization(organization, %{
                 default_language_id: another_language.id
               })

      assert {:error, _} =
               Partners.update_organization(organization, %{active_language_ids: [99_999]})

      assert {:error, _} =
               Partners.update_organization(organization, %{
                 active_language_ids: [another_language.id]
               })
    end

    test "update_organization/2 should update new contact flow" do
      organization = Fixtures.organization_fixture()
      flow = Fixtures.flow_fixture()

      assert {:ok, updated_organization} =
               Partners.update_organization(organization, %{
                 newcontact_flow_id: flow.id
               })

      assert updated_organization.newcontact_flow_id == flow.id
    end

    test "update_organization/2 should update regex flow" do
      organization = Fixtures.organization_fixture()
      flow = Fixtures.flow_fixture()

      assert {:ok, updated_organization} =
               Partners.update_organization(organization, %{
                 regx_flow: %{
                   flow_id: flow.id,
                   regx: "test",
                   regx_opt: "i"
                 }
               })

      assert updated_organization.regx_flow.flow_id == flow.id
      assert updated_organization.regx_flow.regx == "test"
      assert updated_organization.regx_flow.regx_opt == "i"
    end

    test "update_organization/2 with organization new contact flow update is_pinned status of flow" do
      # organization with newcontact flow as nil
      organization = Fixtures.organization_fixture()

      flow =
        Fixtures.flow_fixture(%{
          name: "Test Flow",
          keywords: ["test_keyword"],
          flow_type: :message,
          version_number: "13.1.0"
        })

      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: false
          },
          newcontact_flow_id: flow.id
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      # organization with newcontact flow same as newly created flow
      assert organization.newcontact_flow_id == flow.id

      # creating new flow
      new_flow =
        Fixtures.flow_fixture(%{
          name: "Test Flow2",
          keywords: ["second_test_keyword"],
          flow_type: :message,
          version_number: "13.1.0"
        })

      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: false
          },
          newcontact_flow_id: new_flow.id
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      # organization with newcontact flow same as second newly created flow
      assert organization.newcontact_flow_id == new_flow.id

      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: false
          },
          newcontact_flow_id: nil
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      # organization with newcontact flow same as nil
      assert organization.newcontact_flow_id == nil
    end

    test "update_organization/2 with organization settings" do
      organization = Fixtures.organization_fixture()
      flow_id = 3

      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: true,
            start_time: ~T[10:00:00],
            end_time: ~T[20:00:00],
            enabled_days: [
              %{
                id: 1,
                enabled: true
              }
            ],
            flow_id: 3,
            default_flow_id: 1
          }
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      assert organization.out_of_office.enabled == true
      assert organization.out_of_office.start_time == ~T[10:00:00]
      day1 = get_in(organization.out_of_office.enabled_days, [Access.at(0)])
      assert day1.enabled == true
      # Days in the input should be updated accordingly, other days should be disabled
      day2 = get_in(organization.out_of_office.enabled_days, [Access.at(1)])
      assert day2.enabled == false

      # also check and ensure that out of office flow is set in flow keywords
      flow_keywords_map = Glific.Flows.flow_keywords_map(organization.id)
      assert flow_keywords_map["draft"]["outofoffice"] == flow_id
      assert flow_keywords_map["published"]["outofoffice"] == flow_id

      # disable out_of_office setting
      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: false
          }
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      assert organization.out_of_office.enabled == false

      # also check and ensure that out of office flow is not set in flow keywords
      flow_keywords_map = Glific.Flows.flow_keywords_map(organization.id)
      assert flow_keywords_map["draft"]["outofoffice"] == nil
      assert flow_keywords_map["published"]["outofoffice"] == nil
    end

    test "update_organization/2 update setting column of organization" do
      organization = Fixtures.organization_fixture()

      # With invalid fields
      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          setting: %{
            something: true,
            lorem: "TRUE"
          }
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      assert is_map_key(organization.setting, :something) == false
      assert is_map_key(organization.setting, :lorem) == false

      # with valid fields
      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          setting: %{
            report_frequency: "MONTHLY",
            run_flow_each_time: true,
            low_balance_threshold: 20,
            send_warning_mail: true
          }
        })

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, update_org_attrs)

      assert organization.setting.report_frequency == "MONTHLY"
      assert organization.setting.run_flow_each_time == true
      assert organization.setting.low_balance_threshold == 20
      assert organization.setting.send_warning_mail == true
    end

    test "delete_organization/1 soft deletes the organization" do
      organization = Fixtures.organization_fixture()
      assert {:ok, %Organization{} = deleted_org} = Partners.delete_organization(organization)
      assert deleted_org.deleted_at != nil

      # Organization record is preserved (accessible by ID)
      assert %Organization{} = Partners.get_organization!(organization.id)

      # But excluded from list queries
      org_list = Partners.list_organizations(%{filter: %{name: organization.name}})
      assert Enum.empty?(org_list)
    end

    test "delete_organization_test_data/1 deletes the organization test data" do
      organization = Fixtures.organization_fixture()

      # add a few messages
      Fixtures.message_fixture(%{organization_id: organization.id})
      Fixtures.message_fixture(%{organization_id: organization.id})

      assert {:ok, organization} == Partners.delete_organization_test_data(organization)
      assert Partners.get_organization!(organization.id) != nil

      {:ok, result} =
        Repo.query("SELECT count(*) FROM contacts WHERE id = #{organization.contact_id}")

      [[count]] = result.rows
      assert count == 1

      {:ok, result} = Repo.query("SELECT count(*) FROM messages")
      [[count]] = result.rows
      assert count == 0
    end

    test "change_organization/1 returns a organization changeset" do
      organization = Fixtures.organization_fixture()
      assert %Ecto.Changeset{} = Partners.change_organization(organization)
    end

    test "list_contacts/1 with multiple contacts" do
      _org0 = Fixtures.organization_fixture(@valid_org_attrs)
      _org1 = Fixtures.organization_fixture(@valid_org_attrs_1)

      assert length(Partners.list_organizations()) >= 2
    end

    test "list_organization/1 with multiple organization filteres" do
      _org0 = Fixtures.organization_fixture(@valid_org_attrs)
      org1 = Fixtures.organization_fixture(@valid_org_attrs_1)

      org_list = Partners.list_organizations(%{filter: %{name: org1.name}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{shortcode: org1.shortcode}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{filter: %{email: org1.email}})
      assert org_list == [org1]

      org_list = Partners.list_organizations(%{order: :asc, filter: %{name: "ABC"}})
      assert org_list == []

      org_list = Partners.list_organizations()
      assert length(org_list) >= 3
    end

    test "list_organizations/1 with foreign key filters" do
      provider = provider_fixture(@valid_attrs)
      default_language = default_language_fixture()

      {:ok, organization} =
        @valid_org_attrs
        |> Map.merge(%{
          bsp_id: provider.id,
          default_language_id: default_language.id,
          active_language_ids: [default_language.id]
        })
        |> Partners.create_organization()

      # we need this to ensure we get the right values set by triggers
      organization = Partners.get_organization!(organization.id)

      assert [organization] == Partners.list_organizations(%{filter: %{bsp: provider.name}})

      assert [organization] ==
               Partners.list_organizations(%{filter: %{name: "Organization Name"}})

      assert [] == Partners.list_organizations(%{filter: %{bsp: "RandomString"}})

      assert [] == Partners.list_organizations(%{filter: %{default_language: "Hindi"}})
    end

    test "ensure that creating organization with out provider give an error" do
      assert {:error, %Ecto.Changeset{}} = Partners.create_organization(@valid_org_attrs)
    end

    test "ensure that creating organization  with same whats app number give an error" do
      organization = Fixtures.organization_fixture(@valid_org_attrs)

      assert {:error, %Ecto.Changeset{}} =
               Map.merge(@valid_org_attrs, %{bsp_id: organization.bsp_id})
               |> Partners.create_organization()
    end

    test "set_out_of_office_values/1 should set values for hours and days" do
      organization = Fixtures.organization_fixture()

      updated_organization = Partners.set_out_of_office_values(organization)
      assert updated_organization.hours == [~T[09:00:00], ~T[20:00:00]]
      assert updated_organization.days == [1, 2, 3, 4, 5]

      update_org_attrs =
        @update_org_attrs
        |> Map.merge(%{
          out_of_office: %{
            enabled: true,
            start_time: ~T[10:00:00],
            end_time: ~T[20:00:00],
            enabled_days: [
              %{id: 1, enabled: true},
              %{id: 2, enabled: true}
            ],
            flow_id: 1
          }
        })

      {:ok, updated_organization} = Partners.update_organization(organization, update_org_attrs)

      organization_with_set_values = Partners.set_out_of_office_values(updated_organization)
      assert organization_with_set_values.hours == [~T[10:00:00], ~T[20:00:00]]
      assert organization_with_set_values.days == [1, 2]
    end

    test "active_organizations/0 should return list of active organizations" do
      organization = Fixtures.organization_fixture()
      organizations = Partners.active_organizations([])
      assert organizations[organization.id] != nil

      {:ok, _} = Partners.update_organization(organization, %{is_active: false})
      organizations = Partners.active_organizations([])
      assert organizations[organization.id] == nil
    end

    test "organization/1 should return cached data" do
      organization_id = Fixtures.get_org_id()
      organization = Partners.organization(organization_id)

      assert organization != nil
      assert organization.hours != nil
      assert organization.days != nil
    end

    test "organization/1 should return data if key is a shortcode and cache it" do
      global_organization_id = 0
      organization = Fixtures.organization_fixture(%{shortcode: "new_org"})

      # remove organization data from cache which might be added by fixture
      Caches.remove(global_organization_id, [
        {:organization, organization.id},
        {:organization, organization.shortcode}
      ])

      organization_to_be_cached = Partners.organization(organization.shortcode)

      assert organization_to_be_cached.id == organization.id

      # check whether organization is cached
      assert {:ok, %Partners.Organization{}} =
               Caches.get(global_organization_id, {:organization, organization.shortcode})

      #  with wrong shortcode it returns an error
      assert {:error, _} = Partners.organization("wrong_shortcode")
    end

    test "organization/1 should return cached active languages" do
      organization = Fixtures.organization_fixture() |> Repo.preload(:default_language)

      default_language = organization.default_language
      organization = Partners.organization(organization.id)

      assert organization.languages == [default_language]
    end

    test "organization_contact_id/1 by id should return cached organization's contact id" do
      organization_id = Fixtures.get_org_id()

      assert Partners.organization_contact_id(organization_id) > 0
    end

    test "organization_language_id/1 by id should return cached organization's default langauage id" do
      organization = Fixtures.organization_fixture()
      Partners.organization(organization.id)

      assert Partners.organization_language_id(organization.id) ==
               organization.default_language_id
    end

    test "organization_timezone/1 by id should return cached organization's timezone" do
      organization_id = Fixtures.get_org_id()
      assert Partners.organization_timezone(organization_id) != nil
    end

    test "organization_out_of_office_summary/1 by id should return cached data" do
      organization = Fixtures.organization_fixture()
      organization = Partners.organization(organization.id)

      hours = organization.hours
      days = organization.days
      assert hours != nil
      assert days != nil
    end

    test "perform_all/3 should run handler for all active organizations" do
      organization = Fixtures.organization_fixture()

      contact =
        Fixtures.contact_fixture(%{
          bsp_status: :session_and_hsm,
          optin_time: Timex.shift(DateTime.utc_now(), hours: -26),
          last_message_at: Timex.shift(DateTime.utc_now(), hours: -25),
          organization_id: organization.id
        })

      Partners.perform_all(&Contacts.update_contact_status/2, %{}, [])

      curr_org_id = Repo.get_organization_id()
      Repo.put_organization_id(organization.id)
      updated_contact = Contacts.get_contact!(contact.id)
      assert updated_contact.bsp_status == :hsm
      Repo.put_organization_id(curr_org_id)
    end
  end

  describe "organization's credentials" do
    alias Glific.{
      Contacts,
      Fixtures,
      Partners,
      Partners.Credential,
      Partners.Organization,
      Seeds.SeedsDev
    }

    @opted_in_contact_phone "8989898989"

    setup do
      default_provider = SeedsDev.seed_providers()
      SeedsDev.seed_organizations(default_provider)

      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                "status" => "success",
                "users" => [
                  %{
                    "countryCode" => "91",
                    "lastMessageTimeStamp" => 1_600_402_466_679,
                    "optinSource" => "URL",
                    "optinStatus" => "OPT_IN",
                    "optinTimeStamp" => 1_598_338_828_546,
                    "phoneCode" => "91" <> @opted_in_contact_phone
                  }
                ]
              })
          }
      end)

      :ok
    end

    test "create_credential/1 with valid data creates a credential",
         %{organization_id: organization_id} = _attrs do
      provider = provider_fixture()

      valid_attrs = %{
        shortcode: provider.shortcode,
        secrets: %{api_key: "test_value"},
        organization_id: organization_id
      }

      assert {:ok, %Credential{} = credential} = Partners.create_credential(valid_attrs)

      assert credential.secrets == valid_attrs.secrets

      # credential with same provider shortcode for the organization should not be allowed
      valid_attrs = %{
        shortcode: provider.shortcode,
        secrets: %{provider_key: "test_value_2"},
        organization_id: organization_id
      }

      assert {:error, %Ecto.Changeset{}} = Partners.create_credential(valid_attrs)
    end

    test "get_credential/1 returns the organization credential for given shortcode",
         %{organization_id: organization_id} = _attrs do
      provider = provider_fixture()

      valid_attrs = %{
        shortcode: provider.shortcode,
        secrets: %{api_key: "test_value"},
        organization_id: organization_id
      }

      {:ok, _credential} = Partners.create_credential(valid_attrs)

      assert {:ok, %Credential{}} =
               Partners.get_credential(%{
                 organization_id: organization_id,
                 shortcode: provider.shortcode
               })
    end

    test "update_credential/1 with valid data updates an organization's credential",
         %{organization_id: organization_id} = _attrs do
      provider = provider_fixture()

      valid_attrs = %{
        shortcode: provider.shortcode,
        secrets: %{api_key: "test_value"},
        organization_id: organization_id
      }

      {:ok, credential} = Partners.create_credential(valid_attrs)

      valid_update_attrs = %{
        secrets: %{api_key: "updated_test_value"}
      }

      assert {:ok, %Credential{} = credential} =
               Partners.update_credential(
                 credential,
                 valid_update_attrs
               )

      assert credential.secrets == valid_update_attrs.secrets
    end

    test "update_credential/2 for gupshup enterprise should update credentials",
         %{organization_id: organization_id} = _attrs do
      {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup_enterprise"})

      assert {:ok, %Credential{} = credential} =
               Repo.fetch_by(Credential, %{provider_id: provider.id})

      valid_update_attrs = %{
        keys: %{},
        shortcode: provider.shortcode,
        secrets: %{"user_id" => "updated_user_id", "password" => "updated_password"},
        organization_id: organization_id
      }

      {:ok, updated_credential} = Partners.update_credential(credential, valid_update_attrs)
      assert "updated_password" == updated_credential.secrets["password"]
      assert "updated_user_id" == updated_credential.secrets["user_id"]
    end

    test "update_credential/2 for gupshup  should update credentials",
         %{organization_id: organization_id} = _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               Jason.encode!(%{
                 "partnerAppsList" => [%{"id" => "app_id", "name" => "some_app"}]
               })
           }}

        %{method: :post} ->
          {:error,
           %Tesla.Env{
             status: 400,
             body: %{
               "error" => "Re-linking"
             }
           }}
      end)

      {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

      assert {:ok, %Credential{} = credential} =
               Repo.fetch_by(Credential, %{provider_id: provider.id})

      valid_update_attrs = %{
        keys: %{},
        shortcode: provider.shortcode,
        secrets: %{"app_name" => "some_app", "api_key" => "some_key"},
        organization_id: organization_id
      }

      {:ok, updated_credential} = Partners.update_credential(credential, valid_update_attrs)
      assert "some_app" == updated_credential.secrets["app_name"]
      assert "app_id" == updated_credential.secrets["app_id"]
    end

    test "update_credential/2 for gupshup with empty creds, should error out",
         %{organization_id: organization_id} = _attrs do
      {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

      assert {:ok, %Credential{} = credential} =
               Repo.fetch_by(Credential, %{provider_id: provider.id})

      valid_update_attrs = %{
        keys: %{},
        shortcode: provider.shortcode,
        secrets: %{"app_name" => "", "api_key" => ""},
        organization_id: organization_id
      }

      {:error, "App Name and API Key can't be empty"} =
        Partners.update_credential(credential, valid_update_attrs)
    end

    test "update_credential/2 for gupshup with linking error",
         %{organization_id: organization_id} = _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          {:error,
           %Tesla.Env{
             status: 400,
             body:
               Jason.encode!(%{
                 "error" => "some error"
               })
           }}

        %{method: :post} ->
          {:error,
           %Tesla.Env{
             status: 400,
             body: %{
               "error" => "non-relink"
             }
           }}
      end)

      {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

      assert {:ok, %Credential{} = credential} =
               Repo.fetch_by(Credential, %{provider_id: provider.id})

      valid_update_attrs = %{
        keys: %{},
        shortcode: provider.shortcode,
        secrets: %{"app_name" => "some_app", "api_key" => "some_key"},
        organization_id: organization_id
      }

      {:error, _} = Partners.update_credential(credential, valid_update_attrs)

      assert {:ok, %Credential{} = credential} =
               Repo.fetch_by(Credential, %{provider_id: provider.id})

      assert credential.secrets["app_id"] == "NA"
    end

    test "update_credential/2 for gupshup with first time linking",
         %{organization_id: organization_id} = _attrs do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               Jason.encode!(%{
                 "partnerApps" => %{
                   "id" => "app_id"
                 }
               })
           }}
      end)

      {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

      assert {:ok, %Credential{} = credential} =
               Repo.fetch_by(Credential, %{provider_id: provider.id})

      valid_update_attrs = %{
        keys: %{},
        shortcode: provider.shortcode,
        secrets: %{"app_name" => "some_app", "api_key" => "some_key"},
        organization_id: organization_id
      }

      {:ok, updated_credential} = Partners.update_credential(credential, valid_update_attrs)
      assert "some_app" == updated_credential.secrets["app_name"]
      assert "app_id" == updated_credential.secrets["app_id"]
    end

    test "update_credential/2 for gupshup should send email notification to support",
         %{organization_id: organization_id} = _attrs do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               Jason.encode!(%{
                 "partnerAppsList" => [%{"id" => "test_app_id", "name" => "test_app"}]
               })
           }}

        %{method: :post} ->
          {:error, %Tesla.Env{status: 400, body: %{"error" => "Re-linking"}}}
      end)

      {:ok, provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

      assert {:ok, %Credential{} = credential} =
               Repo.fetch_by(Credential, %{provider_id: provider.id})

      valid_update_attrs = %{
        keys: %{},
        shortcode: provider.shortcode,
        secrets: %{"app_name" => "test_app", "api_key" => "test_key"},
        organization_id: organization_id
      }

      {:ok, _updated_credential} = Partners.update_credential(credential, valid_update_attrs)
      # Assert that an email was sent to support
      assert_email_sent(fn email ->
        email.subject =~ "Gupshup Setup Completed" and
          email.to == [Mailer.glific_support()]
      end)

      # Verify email was logged
      assert MailLog.count_mail_logs(%{
               filter: %{organization_id: organization_id, category: "Gupshup Setup"}
             }) == 1
    end

    test "update_credential/2 for bigquery should call create bigquery dataset",
         %{organization_id: organization_id} = _attrs do
      valid_attrs = %{
        shortcode: "bigquery",
        secrets: %{},
        organization_id: organization_id
      }

      {:ok, credential} = Partners.create_credential(valid_attrs)

      valid_update_attrs = %{
        secrets: %{"service_account" => %{}},
        is_active: false,
        organization_id: organization_id
      }

      {:ok, _credential} = Partners.update_credential(credential, valid_update_attrs)
    end

    test "update_credential/2 for maytapi should update credentials" do
      org = SeedsDev.seed_organizations()

      Tesla.Mock.mock(fn
        %{
          method: :get,
          url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/listPhones"
        } ->
          {:ok, %Tesla.Env{status: 200, body: ~s([
            {
              "id": 45976,
              "name": "",
              "number": "918887048283",
              "status": "active",
              "type": "whatsapp",
              "data": {"mobile_proxy": true},
              "multi_device": true
            }
          ])}}

        %{
          method: :get,
          url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/45976/getGroups"
        } ->
          {:ok, %Tesla.Env{status: 200, body: ~s({
            "count": 1,
            "data": [
              {
                "id": "120363411352918646@g.us",
                "name": "test",
                "admins": ["918887048283@c.us"],
                "participants": ["918887048283@c.us", "914287925084@c.us"],
                "config": {
                  "approveNewMembers": false,
                  "disappear": false,
                  "edit": "all",
                  "membersCanAddMembers": false,
                  "send": "all"
                }
              }
            ]
          })}}

        %{
          method: :post,
          url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/setWebhook"
        } ->
          {:ok, %Tesla.Env{status: 200, body: ~s({"success": true})}}
      end)

      {:ok, credential} =
        Partners.create_credential(%{
          organization_id: org.id,
          shortcode: "maytapi",
          keys: %{},
          secrets: %{
            "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
            "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
          }
        })

      valid_update_attrs = %{
        keys: %{},
        secrets: %{
          "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
          "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
        },
        is_active: true,
        organization_id: org.id,
        shortcode: "maytapi"
      }

      assert {:ok, _cred} = Partners.update_credential(credential, valid_update_attrs)

      assert_enqueued(worker: WAWorker, prefix: "global")

      assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :wa_group)

      notifications =
        Repo.all(
          from n in Notification,
            where: n.organization_id == ^org.id and n.category == "WhatsApp Groups",
            order_by: [desc: n.inserted_at]
        )

      messages = Enum.map(notifications, & &1.message)

      assert "Syncing of WhatsApp groups and contacts has started in the background." in messages

      assert "Syncing of WhatsApp groups and contacts has been completed successfully." in messages

      severities = Enum.map(notifications, & &1.severity)
      assert Notifications.types().info in severities
    end

    test "update_credential/2 for maytapi should not update credentials with wrong payload" do
      org = SeedsDev.seed_organizations()

      {:ok, credential} =
        Partners.create_credential(%{
          organization_id: org.id,
          shortcode: "maytapi",
          keys: %{},
          secrets: %{
            "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
            "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
          }
        })

      valid_update_attrs = %{
        keys: %{},
        secrets: %{
          "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
          "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
        },
        is_active: true,
        organization_id: org.id,
        shortcode: "maytapi"
      }

      Tesla.Mock.mock(fn
        %{
          method: :get,
          url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/listPhones"
        } ->
          {:ok, %Tesla.Env{status: 200, body: ~s([
            {
              "id": 45976,
              "name": "",
              "number": "918887048283",
              "type": "whatsapp",
              "data": {"mobile_proxy": true},
              "multi_device": true
            }
          ])}}
      end)

      assert {:ok, _cred} = Partners.update_credential(credential, valid_update_attrs)

      assert_enqueued(worker: WAWorker, prefix: "global")

      assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
               Oban.drain_queue(queue: :wa_group)

      notifications =
        Repo.all(
          from n in Notification,
            where: n.organization_id == ^org.id and n.category == "WhatsApp Groups",
            order_by: [desc: n.inserted_at]
        )

      messages = Enum.map(notifications, & &1.message)

      assert "Syncing of WhatsApp groups and contacts has started in the background." in messages

      assert "WhatsApp group data sync failed: \"No active phones available\"" in messages

      severities = Enum.map(notifications, & &1.severity)
      assert Notifications.types().info in severities
      assert Notifications.types().critical in severities
    end

    test "get_global_field_map/2 for organization should return global fields map" do
      organization = Fixtures.organization_fixture(%{fields: %{"org_name" => "Glific"}})
      global_fields = Partners.get_global_field_map(organization.id)
      assert global_fields == %{"org_name" => "Glific"}
    end

    test "valid_bsp?/2 for credentials should return true when credentials are valid", _attrs do
      {:ok, gupshup_provider} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

      {:ok, gupshup_credentials} = Repo.fetch_by(Credential, %{provider_id: gupshup_provider.id})

      assert true == gupshup_credentials |> Repo.preload([:provider]) |> Partners.valid_bsp?()

      {:ok, gupshup_enterprise_provider} =
        Repo.fetch_by(Provider, %{shortcode: "gupshup_enterprise"})

      assert {:ok, gupshup_enterprise_credentials} =
               Repo.fetch_by(Credential, %{provider_id: gupshup_enterprise_provider.id})

      assert true ==
               gupshup_enterprise_credentials
               |> Repo.preload([:provider])
               |> Partners.valid_bsp?()
    end

    @default_goth_json """
    {
    "project_id": "DEFAULT PROJECT ID",
    "private_key_id": "DEFAULT API KEY",
    "client_email": "DEFAULT CLIENT EMAIL",
    "private_key": "DEFAULT PRIVATE KEY"
    }
    """

    test "get_organization_services/2 for organization should return organization services key value pair",
         %{organization_id: organization_id} = _attrs do
      organization_services = Partners.get_organization_services()

      assert organization_services[organization_id]["bigquery"] == false
      assert organization_services[organization_id]["dialogflow"] == false
      assert organization_services[organization_id]["fun_with_flags"] == true
      assert organization_services[organization_id]["google_cloud_storage"] == false

      valid_attrs = %{
        secrets: %{"service_account" => @default_goth_json},
        is_active: true,
        shortcode: "bigquery",
        organization_id: organization_id
      }

      {:ok, _credential} = Partners.create_credential(valid_attrs)
      updated_organization_services = Partners.get_organization_services()

      assert updated_organization_services[organization_id]["bigquery"] == true
      assert updated_organization_services[organization_id]["dialogflow"] == false
      assert updated_organization_services[organization_id]["fun_with_flags"] == true
      assert updated_organization_services[organization_id]["google_cloud_storage"] == false
    end

    test "get_org_services_by_id/1 for organization should return organization services key value pair by id",
         %{organization_id: organization_id} = _attrs do
      organization_services = Partners.get_org_services_by_id(organization_id)

      assert organization_services["bigquery"] == false
      assert organization_services["dialogflow"] == false
      assert organization_services["fun_with_flags"] == true
      assert organization_services["google_cloud_storage"] == false

      valid_attrs = %{
        secrets: %{"service_account" => @default_goth_json},
        is_active: true,
        shortcode: "bigquery",
        organization_id: organization_id
      }

      {:ok, _credential} = Partners.create_credential(valid_attrs)
      updated_organization_services = Partners.get_org_services_by_id(organization_id)

      assert updated_organization_services["bigquery"] == true
      assert updated_organization_services["dialogflow"] == false
      assert updated_organization_services["fun_with_flags"] == true
      assert updated_organization_services["google_cloud_storage"] == false
    end

    test "get_goth_token/2 should return goth token",
         %{organization_id: organization_id} = _attrs do
      with_mock(
        Goth.Token,
        [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        valid_attrs = %{
          shortcode: "bigquery",
          secrets: %{
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        }

        Glific.Caches.remove(organization_id, [{:provider_token, "bigquery"}])

        {:ok, _credential} = Partners.create_credential(valid_attrs)

        token = Partners.get_goth_token(organization_id, "bigquery")

        assert token != nil
      end
    end

    test "get_token/1 should return goth token for gcs",
         %{organization_id: organization_id} = _attrs do
      with_mock(
        Goth.Token,
        [],
        fetch: fn _url ->
          {:ok, %{token: "0xFAKETOKEN_Q=", expires: System.system_time(:second) + 120}}
        end
      ) do
        valid_attrs = %{
          shortcode: "google_cloud_storage",
          secrets: %{
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        }

        Glific.Caches.remove(organization_id, [{:provider_token, "google_cloud_storage"}])

        {:ok, _credential} = Partners.create_credential(valid_attrs)

        token = Partners.get_goth_token(organization_id, "google_cloud_storage")

        assert token != nil
      end
    end

    test "get_token/1 on returning account not found error in goth token should disable GCS",
         %{organization_id: organization_id} = _attrs do
      with_mocks([
        {
          Goth.Token,
          [:passthrough],
          [
            fetch: fn _url ->
              {:error,
               "Could not retrieve token, response: {\"error\":\"invalid_grant\",\"error_description\":\"Invalid grant: account not found\"}"}
            end
          ]
        }
      ]) do
        valid_attrs = %{
          shortcode: "google_cloud_storage",
          secrets: %{
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        }

        Glific.Caches.remove(organization_id, [{:provider_token, "google_cloud_storage"}])

        {:ok, _credential} = Partners.create_credential(valid_attrs)

        assert true == is_nil(Partners.get_goth_token(organization_id, "google_cloud_storage"))

        {:ok, cred} =
          Partners.get_credential(%{
            organization_id: organization_id,
            shortcode: "google_cloud_storage"
          })

        assert cred.is_active == false
      end
    end

    test "get_token/1 on return error in goth token should disable BigQuery",
         %{organization_id: organization_id} = _attrs do
      with_mocks([
        {
          Goth.Token,
          [:passthrough],
          [
            fetch: fn _url ->
              {:error,
               "Could not retrieve token, response: {\"error\":\"invalid_grant\",\"error_description\":\"Invalid grant: account not found\"}"}
            end
          ]
        }
      ]) do
        valid_attrs = %{
          shortcode: "bigquery",
          secrets: %{
            "service_account" =>
              Jason.encode!(%{
                project_id: "DEFAULT PROJECT ID",
                private_key_id: "DEFAULT API KEY",
                client_email: "DEFAULT CLIENT EMAIL",
                private_key: "DEFAULT PRIVATE KEY"
              })
          },
          is_active: true,
          organization_id: organization_id
        }

        Glific.Caches.remove(organization_id, [{:provider_token, "bigquery"}])

        {:ok, _credential} = Partners.create_credential(valid_attrs)

        assert true ==
                 is_nil(Partners.get_goth_token(organization_id, "bigquery"))

        {:ok, cred} =
          Partners.get_credential(%{organization_id: organization_id, shortcode: "bigquery"})

        assert cred.is_active == false
      end
    end

    test "disable_credential/2 should disable the credentials and create notification",
         %{organization_id: organization_id} = _attrs do
      provider = provider_fixture()

      valid_attrs = %{
        shortcode: provider.shortcode,
        secrets: %{api_key: "test_value"},
        organization_id: organization_id,
        is_active: true
      }

      assert {:ok, %Credential{} = credential} = Partners.create_credential(valid_attrs)

      assert credential.is_active == true

      # credential with same provider shortcode for the organization should not be allowed
      Partners.disable_credential(
        organization_id,
        provider.shortcode,
        "Multiple credentials found for same shortcode"
      )

      {:ok, credential} =
        Repo.fetch_by(Credential, %{
          organization_id: organization_id,
          provider_id: provider.id
        })

      {:ok, notification} =
        Repo.fetch_by(Notification, %{
          organization_id: organization_id
        })

      assert notification.message ==
               "Disabling shortcode 1. Multiple credentials found for same shortcode"

      assert credential.is_active == false
    end

    test "send_dashboard_report/2 send mail to organization about their chatbot report" do
      organization = Fixtures.organization_fixture()

      assert {:ok, %Organization{} = organization} =
               Partners.update_organization(organization, %{
                 setting: %{report_frequency: "WEEKLY"}
               })

      assert {:ok, %{message: _error}} =
               Partners.send_dashboard_report(organization.id, %{frequency: "WEEKLY"})
    end

    test "credentials should be audited with ExAudit",
         %{organization_id: organization_id} = _attrs do
      provider = provider_fixture()

      valid_attrs = %{
        shortcode: provider.shortcode,
        secrets: %{api_key: "test_audit_value"},
        organization_id: organization_id
      }

      {:ok, credential} = Partners.create_credential(valid_attrs)

      # History should not have secrets in the patch
      [created_history] = Repo.history(credential, skip_organization_id: true)
      assert :secrets not in Map.keys(created_history.patch)
    end
  end

  describe "get_resource_local_path/2" do
    test "successfull file download to local" do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "sample data"
          }
      end)

      assert {:ok, "template-asset-sample.png"} =
               PartnerAPI.get_resource_local_path("sample.png", "sample")

      File.rm("template-asset-sample.png")
    end

    test "file download to local failed" do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          {:error, "error"}
      end)

      assert {:error, _} = PartnerAPI.get_resource_local_path("sample.png", "sample")
    end
  end

  describe "delete_local_resource/1" do
    test "successfull file delete from local" do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body: "sample data"
          }
      end)

      assert {:ok, "template-asset-sample.png"} =
               PartnerAPI.get_resource_local_path("sample.png", "sample")

      assert :ok = PartnerAPI.delete_local_resource("sample.png", "sample")
    end

    test "local file deletion failed" do
      assert {:error, :enoent} = PartnerAPI.delete_local_resource("sample2.png", "sample2")
    end
  end

  describe "test gupshup error handling on applying for template/3" do
    test "successfull gupshup error handling for HSM template" do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 400,
            body:
              "{\"message\":\"Template Already exists with same namespace and elementName and languageCode\",\"status\":\"error\"}"
          }
      end)

      assert {:error,
              "Template Already exists with same namespace and elementName and languageCode"} =
               PartnerAPI.apply_for_template(1, %{elementName: "trial"})
    end
  end

  describe "test sucessful response on the api: applying for template/3" do
    test "successfull response for applying for HSM template" do
      Tesla.Mock.mock(fn
        %{method: :post} ->
          %Tesla.Env{
            status: 200,
            body: "{\"message\":\"Success\",\"status\":\"error\"}"
          }
      end)

      assert {:ok, %{"message" => "Success", "status" => "error"}} =
               PartnerAPI.apply_for_template(1, %{elementName: "trial"})
    end
  end

  describe "Partner.set_subscription/4" do
    setup do
      error = %{
        "status" => "error",
        "message" => "Duplicate component"
      }

      Tesla.Mock.mock(fn
        %{method: :post, url: "https://partner.gupshup.io/partner/account/login"} ->
          %Tesla.Env{
            status: 200,
            body:
              JSON.encode!(%{
                "token" => "token"
              })
          }

        %{method: :post, body: body} ->
          if String.contains?(body, "error-ngrok.app") do
            %Tesla.Env{
              status: 400,
              body: JSON.encode!(error)
            }
          else
            %Tesla.Env{
              status: 200,
              body:
                JSON.encode!(%{
                  "status" => "success",
                  "subscription" => %{
                    "active" => true,
                    "createdOn" => 1_748_489_845_881,
                    "id" => "10380410",
                    "mode" => 1143,
                    "modes" => [
                      "SENT",
                      "DELIVERED",
                      "READ",
                      "OTHERS",
                      "FAILED",
                      "MESSAGE",
                      "ENQUEUED"
                    ],
                    "modifiedOn" => 1_748_489_845_881,
                    "showOnUI" => false,
                    "tag" => "webhook_glific",
                    "url" =>
                      Regex.run(~r/&url=([^&]+?)&version/, body) |> List.last() |> URI.decode(),
                    "version" => 2
                  }
                })
            }
          end

        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            body:
              Jason.encode!(%{
                partner_app_token: "sk_test_partner_app_token"
              })
          }
      end)

      {:ok, %{error: error}}
    end

    test "enable webhook subscription for an app" do
      org = SeedsDev.seed_organizations()

      {:ok, data} = PartnerAPI.set_subscription(org.id, nil, ["NEW_EVENT"])
      assert %{"status" => "success"} = data
    end

    test "enable webhook subscription for an app, passing callback url" do
      org = SeedsDev.seed_organizations()

      {:ok, data} =
        PartnerAPI.set_subscription(org.id, "https://4bff-116-68-82-101.ngrok-free.app/gupshup")

      assert %{
               "status" => "success",
               "subscription" => %{"url" => "https://4bff-116-68-82-101.ngrok-free.app/gupshup"}
             } = data
    end

    test "enable webhook subscription for an app, duplicate webhook error", state do
      org = SeedsDev.seed_organizations()

      {:error, %{body: body}} =
        PartnerAPI.set_subscription(org.id, "https://error-ngrok.app/gupshup")

      assert body ==
               JSON.encode!(state.error)
    end
  end
end
