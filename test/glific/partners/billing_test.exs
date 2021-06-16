defmodule Glific.BillingTest do
  use Glific.DataCase
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  alias Glific.{
    Fixtures,
    Partners,
    Partners.Billing,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    HTTPoison.start()
    ExVCR.Config.cassette_library_dir("test/support/ex_vcr")
    :ok
  end

  describe "billings" do
    @valid_attrs %{
      name: "test billing name",
      email: "testbilling@gmail.com",
      currency: "inr"
    }

    @invalid_attrs %{
      name: "test billing name",
      currency: "inr"
    }

    test "create/1 with valid data should create billing", %{organization_id: organization_id} do
      use_cassette "create_billing" do
        attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

        assert {:ok, %Billing{} = billing} =
                 Partners.get_organization!(organization_id)
                 |> Billing.create(attrs)

        assert billing.name == "test billing name"
        assert billing.email == "testbilling@gmail.com"
        assert billing.currency == "inr"
      end
    end

    test "create/1 with invalid data should return error", %{organization_id: organization_id} do
      attrs = Map.merge(@invalid_attrs, %{organization_id: organization_id})

      {:error, error_message} =
        Partners.get_organization!(organization_id)
        |> Billing.create(attrs)

      assert error_message == "email is not set"
    end

    test "update_billing/2 should update billling", %{organization_id: organization_id} do
      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      billing = Fixtures.billing_fixture(attrs)
      assert {:ok, %Billing{} = billing} = Billing.update_billing(billing, %{currency: "usd"})
      assert billing.name == "test billing name"
      assert billing.email == "testbilling@gmail.com"
      assert billing.currency == "usd"
    end

    test "delete_billing/1 should delete billing", attrs do
      billing = Fixtures.billing_fixture(attrs)
      assert {:ok, %Billing{}} = Billing.delete_billing(billing)
      Billing.get_billing(%{name: "test billing name"})
      assert true == is_nil(Billing.get_billing(%{name: "test billing name"}))
    end

    test "get_billing/1 should get billing matching attrs", attrs do
      _billing =
        attrs
        |> Map.merge(%{name: "some name"})
        |> Fixtures.billing_fixture()

      billing = Billing.get_billing(%{name: "some name"})
      assert billing.name == "some name"
    end

    test "create_subscription/1 with valid data should create subscription", %{
      organization_id: organization_id
    } do
      use_cassette "create_subscription" do
        stripe_payment_method_id = "some_stripe_payment_method_id"

        assert {:ok, subscription} =
                 Partners.get_organization!(organization_id)
                 |> Billing.create_subscription(%{
                   stripe_payment_method_id: stripe_payment_method_id
                 })

        assert subscription == %{status: :active}
      end
    end

    test "apply_coupon/2 should validate " do
      use_cassette "apply_coupon" do
        Billing.apply_coupon("test_invoice_id", %{coupon_code: "mWH5sOOw"})
      end
    end

    test "customer_portal_link/1 with valid data should return url", attrs do
      use_cassette "customer_portal_link" do
        attrs
        |> Map.merge(%{name: "Akhilesh Negi"})
        |> Fixtures.billing_fixture()

        billing = Billing.get_billing(%{name: "Akhilesh Negi"})

        assert {:ok, response} = Billing.customer_portal_link(billing)
        assert response.url == "https://billing.stripe.com/session/test_session_id"
        assert response.return_url == "https://test.tides.coloredcow.com/settings/billing"
      end
    end

    test "update_payment_method/1 with valid data should update payment method", %{
      organization_id: organization_id
    } do
      use_cassette "update_payment_method" do
        payment_method_id = "pm_1IgT1nEMShkCsLFnOd4GdL9I"

        assert {:ok, subscription} =
                 Partners.get_organization!(organization_id)
                 |> Billing.update_payment_method(payment_method_id)

        assert subscription.stripe_payment_method_id == "pm_1IgT1nEMShkCsLFnOd4GdL9I"
      end
    end

    test "update_monthly_usage/1 should update usage of metered subscription item", %{
      organization_id: organization_id
    } do
      _consulting_hour = Fixtures.consulting_hour_fixture(%{organization_id: organization_id})

      Map.merge(@valid_attrs, %{
        organization_id: organization_id,
        stripe_subscription_items: %{
          price_1IdZbfEMShkCsLFn8TF0NLPO: "test_monthly_id",
          price_1IdZe5EMShkCsLFncGatvTCk: "si_test_subscription_id"
        }
      })
      |> Fixtures.billing_fixture()

      use_cassette "update_monthly_usage" do
        Billing.update_monthly_usage()
      end
    end
  end
end
