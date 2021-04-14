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
    :ok
  end

  describe "billings" do
    @valid_attrs %{
      name: "test billing name",
      email: "testbilling@gmail.com",
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
                 |> Billing.create_subscription(stripe_payment_method_id)

        assert subscription == %{status: :active}
      end
    end
  end
end
