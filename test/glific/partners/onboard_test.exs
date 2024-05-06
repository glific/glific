defmodule Glific.OnboardTest do
  alias Glific.GCS.GcsWorker
  use Glific.DataCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  import Mock

  alias Glific.{
    Fixtures,
    Partners,
    Partners.Organization,
    Registrations,
    Registrations.Registration,
    Saas.Onboard,
    Seeds.SeedsDev
  }

  @valid_attrs %{
    "name" => "First Organization",
    "phone" => "+911234567890",
    "api_key" => "fake api key",
    "app_name" => "fake app name",
    "shortcode" => "short",
    "gstin" => "29PSFCP4894X9Z7",
    "registered_address" => "registered_address",
    "current_address" => "current_address",
    "registration_doc" => %Plug.Upload{
      content_type: "application/pdf",
      filename: "dummy.pdf",
      path: "/"
    }
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    ExVCR.Config.cassette_library_dir("test/support/ex_vcr")

    Tesla.Mock.mock_global(fn
      %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "ok",
              "users" => [1, 2, 3]
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

    :ok
  end

  test "ensure that validations are applied on params while creating an org" do
    registered_address = String.duplicate("lorum epsum", 300)

    attrs =
      @valid_attrs
      |> Map.delete("app_name")
      |> Map.put("email", "foobar")
      |> Map.put("phone", "93'#$%^")
      |> Map.put("shortcode", "glific")
      |> Map.put("gstin", "abcabcabcabcabc")
      |> Map.put("registered_address", registered_address)
      |> Map.delete("current_address")
      |> Map.put("registration_doc", %Plug.Upload{
        content_type: "application/mp3",
        filename: "dummy.pdf",
        path: "/"
      })

    %{
      messages: %{
        phone: "Phone is not valid.",
        shortcode: "Shortcode has already been taken.",
        registered_address: "Field cannot be more than 300 letters.",
        current_address: "Field cannot be empty.",
        api_key_name: "API Key or App Name is empty.",
        registration_doc: "Document should of type PDF, JPEG or PNG"
      },
      is_valid: false
    } = Onboard.setup(attrs)
  end

  test "upload document failed while creating an org" do
    with_mock(
      GcsWorker,
      upload_media: fn _, _, _ -> {:error, "auth error"} end
    ) do
      registered_address = String.duplicate("lorum epsum", 300)

      attrs =
        @valid_attrs
        |> Map.delete("app_name")
        |> Map.put("email", "foobar")
        |> Map.put("phone", "93'#$%^")
        |> Map.put("shortcode", "glific")
        |> Map.put("gstin", "abcabcabcabcabc")
        |> Map.put("registered_address", registered_address)
        |> Map.delete("current_address")
        |> Map.put("registration_doc", %Plug.Upload{
          content_type: "application/pdf",
          filename: "dummy.pdf",
          path: "/"
        })

      %{
        messages: %{
          phone: "Phone is not valid.",
          shortcode: "Shortcode has already been taken.",
          registered_address: "Field cannot be more than 300 letters.",
          current_address: "Field cannot be empty.",
          api_key_name: "API Key or App Name is empty.",
          registration_doc: "Document upload failed, try again"
        },
        is_valid: false
      } = Onboard.setup(attrs)
    end
  end

  test "ensure that sending in valid parameters, creates an organization, contact and credential" do
    with_mock(
      GcsWorker,
      upload_media: fn _, _, _ -> {:ok, %{url: "url"}} end
    ) do
      attrs =
        @valid_attrs
        |> Map.put("shortcode", "new_glific")
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

  describe "update_registration/1" do
    setup do
      with_mock(
        GcsWorker,
        upload_media: fn _, _, _ -> {:ok, %{url: "url"}} end
      ) do
        attrs =
          @valid_attrs
          |> Map.put("shortcode", "new_glific")
          |> Map.put("phone", "919917443995")
          |> Map.put("registration_doc", %Plug.Upload{
            content_type: "application/pdf",
            filename: "dummy.pdf",
            path: "/"
          })

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

        {:ok, org_id: org_id, registration_id: registration_id}
      end
    end

    test "update_registration, without registration_id" do
      assert %{messages: %{registration_id: "Registration ID is empty."}, is_valid: false} =
               Onboard.update_registration(%{})
    end

    test "update_registration, invalid registration_id" do
      assert %{
               messages: %{
                 registration_id: "Registration doesn't exist for given registration ID."
               },
               is_valid: false
             } =
               Onboard.update_registration(%{"registration_id" => 0})
    end

    test "update_registration, valid registration_id", %{registration_id: registration_id} do
      assert %{
               messages: %{},
               is_valid: true,
               registration: _registration_details,
               support_mail: _support_mail
             } =
               Onboard.update_registration(%{"registration_id" => registration_id})
    end

    test "update_registration, invalid params", %{registration_id: reg_id} do
      invalid_params = %{
        "registration_id" => reg_id,
        "billing_frequency" => "twice",
        "finance_poc" => %{
          "name" => String.duplicate(Faker.Person.name(), 20),
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
               messages: _,
               is_valid: false
             } =
               Onboard.update_registration(invalid_params)
    end

    test "update_registration, valid params", %{org_id: org_id, registration_id: reg_id} do
      valid_params = %{
        "registration_id" => reg_id,
        "billing_frequency" => "yearly",
        "finance_poc" => %{
          "name" => Faker.Person.name(),
          "email" => Faker.Internet.email(),
          "designation" => "Sr Accountant",
          "phone" => Faker.Phone.PtBr.phone()
        },
        "submitter" => %{
          "name" => Faker.Person.name(),
          "email" => Faker.Internet.email()
        }
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.billing_frequency == "yearly"
      assert %{"name" => _, "email" => _} = reg.submitter
      assert %{"name" => _, "email" => _, "phone" => _} = reg.finance_poc
      assert %{email: nil} = Partners.get_organization!(org_id)
    end

    test "update_registration, valid signing_details, update's org's email also", %{
      org_id: org_id,
      registration_id: reg_id
    } do
      valid_params = %{
        "registration_id" => reg_id,
        "signing_authority" => %{
          "name" => Faker.Person.name(),
          "email" => Faker.Internet.email(),
          "designation" => "designation"
        }
      }

      assert %{
               messages: _,
               is_valid: true
             } =
               Onboard.update_registration(valid_params)

      {:ok, %Registration{} = reg} = Registrations.get_registration(reg_id)
      assert reg.billing_frequency == "monthly"
      assert %{"name" => _, "email" => _, "designation" => _} = reg.signing_authority
      %{email: email} = Partners.get_organization!(org_id)
      assert !is_nil(email)
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
      "name" => Faker.Person.name(),
      "message" => Faker.Lorem.paragraph(),
      "email" => Faker.Internet.email()
    }

    %{is_valid: true} = Onboard.reachout(invalid_params)
  end
end
