defmodule Glific.BillingTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Partners.Billing
  }

  describe "billings" do
    @valid_attrs %{
      name: "Billing name",
      email: "Billing person email",
      currency: "inr"
    }

    test "create_billing/1 with valid data", %{organization_id: organization_id} do
      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Billing{} = billing} = Billing.create_billing(attrs)
      assert billing.name == "Billing name"
      assert billing.email == "Billing person email"
      assert billing.currency == "inr"
    end

    test "update_billing/2 with valid data updates the tag", %{organization_id: organization_id} do
      attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Billing{} = billing} = Billing.create_billing(attrs)
      assert {:ok, %Billing{} = billing} = Billing.update_billing(billing, %{currency: "usd"})
      assert billing.name == "Billing name"
      assert billing.email == "Billing person email"
      assert billing.currency == "usd"
    end
  end
end
