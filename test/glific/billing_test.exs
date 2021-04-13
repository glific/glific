defmodule Glific.BillingTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Partners.Billing,
  }

  describe "billings" do
    # language id needs to be added dynamically for all the below actions
    @valid_attrs %{
      name: "Billing name",
      email: "Billing person email",
      currency: "inr"
    }

    test "create_billing/1 with valid data", %{organization_id: organization_id} do
      attrs =
        Map.merge(@valid_attrs, %{organization_id: organization_id})

      assert {:ok, %Billing{} = billing} = Billing.create_billing(attrs)
      assert billing.name == "Billing name"
      assert billing.email == "Billing person email"
      assert billing.currency == "inr"
    end
  end
end
