defmodule Glific.OnboardTest do
  alias Glific.GCS.GcsWorker
  use Glific.DataCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  import Mock

  @dummy_phone_number "91783481114"
  alias Faker.Phone

  alias Glific.{
    Contacts,
    Fixtures,
    Mails.NewPartnerOnboardedMail,
    Partners,
    Partners.Organization,
    Partners.Saas,
    Registrations,
    Registrations.Registration,
    Saas.Onboard,
    Seeds.SeedsDev
  }

  @valid_attrs %{
    "name" => "First",
    "phone" => "+911234567890",
    "api_key" => "fake api key",
    "app_name" => "fake app name",
    "shortcode" => "short"
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    SeedsDev.seed_contacts()
    SeedsDev.seed_users()
    ExVCR.Config.cassette_library_dir("test/support/ex_vcr")

    Tesla.Mock.mock_global(fn
      %{method: :get, url: "https://t4d-erp.frappe.cloud/api/resource/Customer/First"} ->
        {:ok, %Tesla.Env{status: 200, body: %{data: %{customer_name: "First"}}}}

      %{method: :put, url: "https://t4d-erp.frappe.cloud/api/resource/Customer/First"} ->
        {:ok, %Tesla.Env{status: 200, body: %{message: "Update successful"}}}

      %{method: :put, url: "https://t4d-erp.frappe.cloud/api/resource/Address/First-Billing"} ->
        {:ok, %Tesla.Env{status: 200, body: %{message: "Update successful"}}}

      %{
        method: :post,
        url: "https://t4d-erp.frappe.cloud/api/resource/Address/First-Permanent/Registered"
      } ->
        {:ok, %Tesla.Env{status: 200, body: %{message: "Update successful"}}}

      %{
        method: :put,
        url: "https://t4d-erp.frappe.cloud/api/resource/Address/First-Permanent/Registered"
      } ->
        {:ok, %Tesla.Env{status: 200, body: %{message: "Update successful"}}}

      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "partnerAppsList" => [%{"name" => "fake app name"}]
            })
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "partnerApps" => %{"name" => "fake app name", "id" => "fake_app_id"},
              "token" => "ks_test_token",
              "status" => "success",
              "templates" => [],
              "template" => %{"id" => Ecto.UUID.generate(), "status" => "PENDING"}
            })
        }
    end)

    :ok
  end

  test "ensure that validations are applied on params while creating an org" do
    attrs =
      @valid_attrs
      |> Map.delete("app_name")
      |> Map.put("email", "foobar")
      |> Map.put("phone", "93'#$%^")
      |> Map.put("shortcode", "glific")

    %{
      messages: %{
        phone: "Phone is not valid.",
        shortcode: "Shortcode has already been taken.",
        api_key_name: "API Key or App Name is empty."
      },
      is_valid: false
    } = Onboard.setup(attrs)
  end

  test "ensure that sending in valid parameters, creates an organization, contact and credential" do
    with_mock(
      GcsWorker,
      upload_media: fn _, _, _ -> {:ok, %{url: "url"}} end
    ) do
      attrs =
        @valid_attrs
        |> Map.put("shortcode", "newglific")
        |> Map.put("phone", "919917443995")

      result = Onboard.setup(attrs)

      assert result.is_valid == true
      assert result.messages == %{}
      assert result.organization != nil
      assert result.contact != nil
      assert result.credential != nil
      assert result.registration_id != nil
    end
  end

  test "ensure that sending in valid parameters, update organization status" do
    with_mock(
      GcsWorker,
      upload_media: fn _, _, _ -> {:ok, %{url: "url"}} end
    ) do
      result = Onboard.setup(@valid_attrs)

      {:ok, organization} =
        Repo.fetch_by(Organization, %{name: result.organization.name}, skip_organization_id: true)

      updated_organization = Onboard.status(organization.id, :active)

      assert updated_organization.is_active == true

      # should update is_approved
      updated_organization = Onboard.status(organization.id, :approved)
      assert updated_organization.is_approved == true
    end
  end

  test "ensure that sending in valid parameters, update organization status as forced_suspension true" do
    result = Onboard.setup(@valid_attrs)

    {:ok, organization} =
      Repo.fetch_by(Organization, %{name: result.organization.name}, skip_organization_id: true)

    updated_organization = Onboard.status(organization.id, :forced_suspension)

    assert updated_organization.is_suspended == true
  end

  test "ensure that sending in valid parameters, update organization status as is_active false and change subscription plan",
       attrs do
    use_cassette "update_subscription_inactive_plan" do
      {:ok, organization} =
        Repo.fetch_by(Organization, %{organization_id: attrs.organization_id},
          skip_organization_id: true
        )

      updated_organization = Onboard.status(organization.id, :suspended)

      assert updated_organization.is_active == false
    end
  end

  test "ensure that sending in valid parameters, update organization status as is_active false for organization without billing" do
    organization = Fixtures.organization_fixture()
    {:ok, organization} = Repo.fetch_by(Organization, %{organization_id: organization.id})

    updated_organization = Onboard.status(organization.id, :inactive)

    assert updated_organization.is_active == false
  end

  test "ensure that sending in valid parameters, delete inactive organization" do
    with_mock(
      GcsWorker,
      upload_media: fn _, _, _ -> {:ok, %{url: "url"}} end
    ) do
      result = Onboard.setup(@valid_attrs)

      {:ok, organization} =
        Repo.fetch_by(Organization, %{name: result.organization.name}, skip_organization_id: true)

      Onboard.delete(organization.id, true)

      assert {:error, ["Elixir.Glific.Partners.Organization", "Resource not found"]} ==
               Repo.fetch_by(Organization, %{name: result.organization.name})
    end
  end

  describe "update_ngo_password/1" do
    test "success case", %{organization_id: org_id} do
      assert {:ok, "User was successfully updated"} = Onboard.update_ngo_password(org_id)
    end
  end

  describe "update_registration/1" do
    setup do
      with_mock(GcsWorker, upload_media: fn _, _, _ -> {:ok, %{url: "url"}} end) do
        attrs =
          @valid_attrs
          |> Map.put("shortcode", "newglific")
          |> Map.put("phone", "919917443995")

        %{organization: %{id: org_id}, registration_id: registration_id} =
          Onboard.setup(attrs)

        Repo.put_process_state(org_id)

        Repo.put_current_user(
          Fixtures.user_fixture(%{
            name: "NGO Test Admin",
            roles: ["manager"],
            organization_id: org_id
          })
        )

        org = Partners.get_organization!(org_id)

        {:ok, org: org, registration_id: registration_id}
      end
    end

    test "update_registration, without registration_id", %{org: org} do
      assert %{messages: %{registration_id: "Registration ID is empty."}, is_valid: false} =
               Onboard.update_registration(%{}, org)
    end

    test "update_registration, invalid registration_id", %{org: org} do
      assert %{
               messages: %{
                 registration_id: "Registration doesn't exist for given registration ID."
               },
               is_valid: false
             } =
               Onboard.update_registration(%{"registration_id" => "0"}, org)
    end

    test "update_registration, valid registration_id", %{
      registration_id: registration_id,
      org: org
    } do
      assert %{
               messages: %{},
               is_valid: true,
               registration: _registration_details
             } =
               Onboard.update_registration(
                 %{"registration_id" => registration_id},
                 org
               )
    end

    test "update_registration, invalid params", %{registration_id: reg_id, org: org} do
      invalid_params = %{
        "registration_id" => reg_id,
        "billing_frequency" => "twice",
        "finance_poc" => %{
          "name" => String.duplicate(Faker.Person.name(), 100),
          "email" => "invalid@.com",
          "designation" => "",
          "phone" => "23"
        },
        "submitter" => %{
          "name" => "",
          "email" => Faker.Internet.email()
        },
        "signing_authority" => %{
          "name" => Faker.Person.name(),
          "email" => Faker.Internet.email(),
          "designation" => "designation"
        }
      }

      assert %{
               messages: %{
                 billing_frequency:
                   "Value should be one of Monthly , Quarterly, Half-Yearly, Annually.",
                 finance_poc_name: "Field cannot be more than 100 letters.",
                 finance_poc_designation: "Field cannot be empty.",
                 finance_poc_email: "Email is not valid.",
                 submitter_name: "Field cannot be empty."
               },
               is_valid: false
             } =
               Onboard.update_registration(invalid_params, org)
    end

    test "update_registration, valid params", %{org: org, registration_id: reg_id} do
      valid_params = %{
        "registration_id" => reg_id,
        "billing_frequency" => "Annually",
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "submitter" => %{
          "first_name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email()
        }
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.billing_frequency == "Annually"
      assert %{"first_name" => _, "email" => _} = reg.submitter
      assert %{"name" => _, "email" => _, "phone" => _} = reg.finance_poc
      assert %{email: nil} = Partners.get_organization!(org.id)
    end

    test "update_registration, valid params in map", %{org: org, registration_id: reg_id} do
      valid_params = %{
        "registration_id" => reg_id,
        "billing_frequency" => "Annually",
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "submitter" => %{
          "first_name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email()
        },
        "terms_agreed" => true
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.billing_frequency == "Annually"
      assert %{"first_name" => _, "email" => _} = reg.submitter
      assert %{"name" => _, "email" => _, "phone" => _} = reg.finance_poc
      assert %{email: nil} = Partners.get_organization!(org.id)
    end

    test "update_registration, when terms_agreed is false", %{org: org, registration_id: reg_id} do
      valid_params = %{
        "registration_id" => reg_id,
        "billing_frequency" => "Annually",
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "submitter" => %{
          "first_name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email()
        },
        "terms_agreed" => false
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.is_disputed == true
    end

    test "update_registration, valid signing_details, update's org's email also", %{
      org: org,
      registration_id: reg_id
    } do
      valid_params = %{
        "registration_id" => reg_id,
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "signing_authority" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "designation"
        },
        "has_submitted" => false
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.billing_frequency == "monthly"
      assert %{"name" => _, "email" => _, "designation" => _} = reg.signing_authority
      %{email: email} = Partners.get_organization!(org.id)
      assert !is_nil(email)

      valid_params = %{
        "registration_id" => reg_id,
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "submitter" => %{
          "first_name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email()
        }
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)
    end

    test "update_registration, terms_agreed and support_staff_acount were false on submission", %{
      org: org,
      registration_id: reg_id
    } do
      valid_params = %{
        "registration_id" => reg_id,
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "signing_authority" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "designation"
        },
        "has_submitted" => false
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.billing_frequency == "monthly"
      assert %{"name" => _, "email" => _, "designation" => _} = reg.signing_authority
      %{email: email} = Partners.get_organization!(org.id)
      assert !is_nil(email)

      valid_params = %{
        "registration_id" => reg_id,
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "submitter" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email()
        },
        "has_submitted" => true
      }

      assert %{
               messages: _,
               is_valid: false
             } =
               Onboard.update_registration(valid_params, org)
    end

    test "update_registration, terms_agreed and support_staff_acount were true on submission", %{
      org: org,
      registration_id: reg_id
    } do
      valid_params = %{
        "registration_id" => reg_id,
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "signing_authority" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "designation"
        },
        "has_submitted" => false
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.billing_frequency == "monthly"
      assert %{"name" => _, "email" => _, "designation" => _} = reg.signing_authority
      %{email: email} = Partners.get_organization!(org.id)
      assert !is_nil(email)

      valid_params = %{
        "org_id" => 8,
        "registration_id" => reg_id,
        "org_details" => %{
          "gstin" => "",
          "registered_address" => %{
            "address_type" => "Billing",
            "address_line1" => "123 Main Street",
            "address_line2" => "Suite 100",
            "city" => "NY",
            "state" => "Uttarakhand",
            "country" => "India",
            "pincode" => "262402"
          },
          "current_address" => %{
            "address_type" => "Billing",
            "address_line1" => "12345 Main Street",
            "address_line2" => "Suite 1002",
            "city" => "NY",
            "state" => "Uttarakhand",
            "country" => "India",
            "pincode" => "262402"
          }
        },
        "billing_frequency" => "Monthly",
        "finance_poc" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Phone.PtBr.phone()
        },
        "submitter" => %{
          "first_name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "designation"
        },
        "signing_authority" => %{
          "name" => Faker.Person.name() |> String.slice(0, 10),
          "email" => Faker.Internet.email(),
          "designation" => "designation"
        },
        "has_submitted" => true,
        "terms_agreed" => true,
        "support_staff_account" => true
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params, org)
    end
  end

  test "reachout/1, invalid params" do
    invalid_params = %{
      "message" => String.duplicate(Faker.Lorem.paragraph(), 300),
      "email" => "invalid@.com"
    }

    %{is_valid: false} = Onboard.reachout(invalid_params)
  end

  test "reachout/1, valid params" do
    invalid_params = %{
      "name" => Faker.Person.name() |> String.slice(0, 24),
      "message" => Faker.Lorem.paragraph() |> String.slice(0, 250),
      "email" => Faker.Internet.email()
    }

    %{is_valid: true} = Onboard.reachout(invalid_params)
  end

  test "send_user_quer mail" do
    assert %Swoosh.Email{} =
             NewPartnerOnboardedMail.user_query_mail(
               %{
                 "name" => Faker.Person.name(),
                 "message" => Faker.Lorem.paragraph(),
                 "email" => Faker.Internet.email()
               },
               Saas.organization_id() |> Partners.get_organization!()
             )
  end

  test "create confirmation t&c mail" do
    assert %Swoosh.Email{} =
             NewPartnerOnboardedMail.confirmation_mail(%{
               "billing_frequency" => "yearly",
               "finance_poc" => %{
                 "name" => Faker.Person.name() |> String.slice(0, 10),
                 "email" => Faker.Internet.email(),
                 "designation" => "Sr Accountant",
                 "phone" => Phone.PtBr.phone()
               },
               "submitter" => %{
                 "name" => Faker.Person.name() |> String.slice(0, 10),
                 "email" => Faker.Internet.email()
               },
               "signing_authority" => %{
                 "name" => Faker.Person.name(),
                 "email" => Faker.Internet.email(),
                 "designation" => "designation"
               },
               "org_details" => %{
                 "current_address" => Faker.Lorem.paragraph(1..30),
                 "gstin" => " 07AAAAA1234A124",
                 "name" => Faker.Company.name(),
                 "registered_address" => Faker.Lorem.paragraph(1..30)
               }
             })
  end

  test "ensure that the suspension data and status are changed after we change status from forced_suspension to active" do
    {:ok, organization} = Repo.fetch_by(Organization, %{name: "Glific"})

    updated_organization = Onboard.status(organization.id, :forced_suspension)

    assert updated_organization.is_suspended == true
    assert updated_organization.suspended_until != nil

    # Change the status to active
    updated_organization = Onboard.status(organization.id, :active)

    assert updated_organization.is_suspended == false
    assert updated_organization.suspended_until == nil
  end

  test "ensure that shortcode and org name are handled correctly" do
    attrs =
      @valid_attrs
      |> Map.put("name", " First")
      |> Map.put("shortcode", "newglific")
      |> Map.put("phone", "919917443995")

    result = Onboard.setup(attrs)

    assert result.organization.name == "First"
    assert result.organization.shortcode == "newglific"
  end

  test "Handling submitting invalid app name" do
    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "partnerAppsList" => []
            })
        }

      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "token" => "ks_test_token",
              "status" => "success",
              "templates" => [],
              "template" => %{"id" => Ecto.UUID.generate(), "status" => "PENDING"}
            })
        }
    end)

    attrs =
      @valid_attrs
      |> Map.put("name", " First")
      |> Map.put("shortcode", "glificnew")
      |> Map.put("phone", "919917443995")

    assert %{is_valid: false} = Onboard.setup(attrs)
  end

  test "Partnerapps api returns error" do
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
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "token" => "ks_test_token",
              "status" => "success",
              "templates" => [],
              "template" => %{"id" => Ecto.UUID.generate(), "status" => "PENDING"}
            })
        }
    end)

    attrs =
      @valid_attrs
      |> Map.put("name", " First")
      |> Map.put("shortcode", "glificnew")
      |> Map.put("phone", "919917443995")

    assert %{is_valid: false} = Onboard.setup(attrs)
  end

  test "Seeding works even if we are creating a new org with an already present shortcode in seed migration" do
    attrs =
      @valid_attrs
      |> Map.put("name", " First")
      |> Map.put("shortcode", "newglific")
      |> Map.put("phone", "919917443995")

    result = Onboard.setup(attrs)

    assert result.organization.name == "First"
    assert result.organization.shortcode == "newglific"

    simulator_contacts =
      Contacts.list_contacts(%{
        filter: %{term: "Glific"},
        organization_id: result.organization.id
      })

    assert length(simulator_contacts) > 0

    {:ok, _} =
      Partners.get_organization!(result.organization.id) |> Partners.delete_organization()

    result = Onboard.setup(attrs)

    assert result.organization.name == "First"
    assert result.organization.shortcode == "newglific"

    # if we don't delete the existing migration, length of simulator_contacts here will be 0
    simulator_contacts =
      Contacts.list_contacts(%{
        filter: %{term: "Glific"},
        organization_id: result.organization.id
      })

    assert length(simulator_contacts) > 0
  end

  test "We don't delete the existing migrations if shortcode doesnt exist" do
    attrs =
      @valid_attrs
      |> Map.put("name", " First")
      |> Map.put("shortcode", "newglific")
      |> Map.put("phone", "919917443995")

    result = Onboard.setup(attrs)

    assert result.organization.name == "First"
    assert result.organization.shortcode == "newglific"

    result = Onboard.setup(attrs |> Map.merge(%{"shortcode" => "glificb"}))

    assert result.organization.name == "First"
    assert result.organization.shortcode == "glificb"

    query =
      from schema in "schema_seeds",
        where: schema.tenant == "newglific",
        select: %{version: schema.version}

    # making sure that migrations are still there for newglific
    assert length(Repo.all(query, skip_organization_id: true)) > 0
  end

  test "onboard setup v2, invalid params" do
    attrs = %{
      "name" => "",
      "email" => "foobar"
    }

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{name: "name", customer_name: "name"}
          }
        }
    end)

    assert %{is_valid: false, messages: %{name: "Field cannot be empty."}} =
             Onboard.setup_v2(attrs)

    attrs = %{
      "name" => "org_name",
      "email" => "foobar"
    }

    assert %{is_valid: false, messages: %{email: "Email is not valid."}} =
             Onboard.setup_v2(attrs)
  end

  test "onboard setup v2, invalid shortcode" do
    attrs = %{
      "name" => "org_name",
      "email" => "foobar@gmail.com"
    }

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{name: "name", customer_name: "name"}
          }
        }
    end)

    assert %{is_valid: false, messages: %{shortcode: "Invalid shortcode." <> _}} =
             Onboard.setup_v2(attrs)
  end

  test "onboard setup v2, valid params" do
    attrs = %{
      "name" => "orgname is acme",
      "email" => "foobar@gmail.com"
    }

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{name: "name", customer_name: "name"}
          }
        }

      %{method: :post, url: _} ->
        {:ok,
         %Tesla.Env{
           status: 201,
           body: %{
             error: nil,
             data: %{
               user_id: 1,
               api_key: "ApiKey abc",
               organization_id: 1,
               organization_name: "test",
               project_name: "test",
               project_id: 91,
               user_email: "abc@kaapi.org"
             },
             metadata: nil,
             success: true
           }
         }}
    end)

    assert %{
             is_valid: true,
             messages: %{},
             organization: organization,
             contact: contact,
             credential: credential
           } =
             Onboard.setup_v2(attrs)

    assert contact.phone == @dummy_phone_number
    assert contact.name == "NGO Main Account"
    user = Repo.preload(contact, [:user])
    assert user.phone == @dummy_phone_number
    assert %{"api_key" => "NA", "app_id" => "NA", "app_name" => "NA"} = credential.secrets
    assert organization.is_active
    assert organization.status == :active
    assert organization.shortcode == "oia"

    # Check if the kaapi feature flag is enabled for the new organization
    assert FunWithFlags.enabled?(:is_kaapi_enabled, for: %{organization_id: organization.id}) ==
             true
  end

  test "onboard setup v2, valid params, but we also pass shortcode" do
    attrs = %{
      "name" => "orgname",
      "email" => "foobar@gmail.com",
      "shortcode" => "org"
    }

    Tesla.Mock.mock(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            data: %{name: "name", customer_name: "name"}
          }
        }

      %{method: :post, url: _} ->
        {:ok,
         %Tesla.Env{
           status: 201,
           body: %{
             error: nil,
             data: %{
               user_id: 1,
               api_key: "ApiKey abc",
               organization_id: 1,
               organization_name: "test",
               project_name: "test",
               project_id: 91,
               user_email: "abc@kaapi.org"
             },
             metadata: nil,
             success: true
           }
         }}
    end)

    assert %{
             is_valid: true,
             messages: %{},
             organization: organization,
             contact: contact,
             credential: credential
           } =
             Onboard.setup_v2(attrs)

    assert contact.phone == @dummy_phone_number
    assert contact.name == "NGO Main Account"
    user = Repo.preload(contact, [:user])
    assert user.phone == @dummy_phone_number
    assert %{"api_key" => "NA", "app_id" => "NA", "app_name" => "NA"} = credential.secrets
    assert organization.is_active
    assert organization.status == :active
    assert organization.shortcode == "org"
  end

  test "onboard setup v2, valid params, but erp api fails" do
    attrs = %{
      "name" => "orgname",
      "email" => "foobar@gmail.com",
      "shortcode" => "org"
    }

    Tesla.Mock.mock(fn
      %{method: :get} ->
        {:error,
         %Tesla.Env{
           status: 500,
           body: %{
             _server_messages: "[{\"message\":\"reason\"}]"
           }
         }}
    end)

    assert %{is_valid: false} = Onboard.setup_v2(attrs)
  end

  test "onboard setup v2, valid params for trial account" do
    saas_org_id = Saas.organization_id()

    {:ok, _saas_gcs_cred} =
      Partners.create_credential(%{
        organization_id: saas_org_id,
        shortcode: "google_cloud_storage",
        keys: %{},
        secrets: %{
          "bucket" => "test-bucket",
          "service_account" => "{\"type\": \"service_account\", \"project_id\": \"test-project\"}"
        },
        is_active: true
      })

    attrs = %{
      "name" => "trial account",
      "email" => "foo@gmail.com",
      "is_trial" => true
    }

    Tesla.Mock.mock(fn
      %{method: :post, url: _} ->
        {:ok,
         %Tesla.Env{
           status: 201,
           body: %{
             error: nil,
             data: %{
               user_id: 1,
               api_key: "ApiKey abc",
               organization_id: 1,
               organization_name: "trial orgname acme",
               project_name: "trial",
               project_id: 91,
               user_email: "abc@kaapi.org"
             },
             metadata: nil,
             success: true
           }
         }}
    end)

    assert %{
             is_valid: true,
             messages: %{},
             organization: organization,
             contact: contact,
             credential: credential
           } =
             Onboard.setup_v2(attrs)

    user = Repo.preload(contact, [:user])
    assert user.phone == @dummy_phone_number
    assert %{"api_key" => "NA", "app_id" => "NA", "app_name" => "NA"} = credential.secrets
    assert organization.is_active

    assert organization.is_trial_org == true
    assert organization.trial_expiration_date == nil
  end
end
