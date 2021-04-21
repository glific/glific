defmodule GlificWeb.Schema.BillingTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  alias Glific.{
    Partners.Billing,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    HTTPoison.start()
    ExVCR.Config.cassette_library_dir("test/support/ex_vcr")
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/billings/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/billings/list.gql")
  load_gql(:customer_portal, GlificWeb.Schema, "assets/gql/billings/customer_portal.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/billings/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/billings/create.gql")
  load_gql(:create_subscription, GlificWeb.Schema, "assets/gql/billings/create_subscription.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/billings/update.gql")
  load_gql(:payment_method, GlificWeb.Schema, "assets/gql/billings/payment_method.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/billings/delete.gql")

  test "delete a billing", %{user: user} do
    name = "Billing name"
    {:ok, billing} = Repo.fetch_by(Billing, %{name: name, organization_id: user.organization_id})
    result = auth_query_gql_by(:delete, user, variables: %{"id" => billing.id})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "deleteBilling", "errors"]) == nil
  end

  test "update a billing", %{user: user} do
    name = "Billing name"

    use_cassette "update_billing" do
      {:ok, billing} =
        Repo.fetch_by(Billing, %{name: name, organization_id: user.organization_id})

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "id" => billing.id,
            "input" => %{
              "email" => "testingbilling@gmail.com"
            }
          }
        )

      assert {:ok, query_data} = result
      email = get_in(query_data, [:data, "updateBilling", "billing", "email"])
      assert email == "testingbilling@gmail.com"
    end
  end

  test "create a billing", %{user: user} do
    use_cassette "create_billing" do
      result =
        auth_query_gql_by(:create, user,
          variables: %{
            "input" => %{
              "name" => "test billing name",
              "email" => "testbilling@gmail.com",
              "currency" => "inr"
            }
          }
        )

      assert {:ok, query_data} = result
      currency = get_in(query_data, [:data, "createBilling", "billing", "currency"])
      assert currency == "inr"
      email = get_in(query_data, [:data, "createBilling", "billing", "email"])
      assert email == "testbilling@gmail.com"
    end
  end

  test "create a billing subscription", %{user: user} do
    use_cassette "create_subscription" do
      result =
        auth_query_gql_by(:create_subscription, user,
          variables: %{
            "input" => %{
              "stripe_payment_method_id" => "some_stripe_payment_method_id"
            }
          }
        )

      assert {:ok, query_data} = result
      assert get_in(query_data, [:data, "createBillingSubscription", "errors"]) == nil
    end
  end

  test "fetch a billing by id", %{user: user} do
    stripe_customer_id = "test_cus_JIdQjmJcjq"

    {:ok, billing} =
      Repo.fetch_by(Billing, %{
        stripe_customer_id: stripe_customer_id,
        organization_id: user.organization_id
      })

    result = auth_query_gql_by(:by_id, user, variables: %{"id" => billing.id})
    assert {:ok, query_data} = result
    billing = get_in(query_data, [:data, "billing", "billing"])
    assert billing["stripe_customer_id"] == stripe_customer_id
  end

  test "fetch active billing organization", %{user: user} do
    stripe_customer_id = "test_cus_JIdQjmJcjq"
    result = auth_query_gql_by(:list, user, variables: %{})
    assert {:ok, query_data} = result
    billing = get_in(query_data, [:data, "getOrganizationBilling", "billing"])
    assert billing["stripe_customer_id"] == stripe_customer_id
    assert billing["is_active"] == true
  end

  test "update payment method", %{user: user} do
    use_cassette "update_payment_method" do
      payment_method_id = "pm_1IgT1nEMShkCsLFnOd4GdL9I"

      result =
        auth_query_gql_by(:payment_method, user,
          variables: %{
            "input" => %{
              "stripe_payment_method_id" => payment_method_id
            }
          }
        )

      assert {:ok, query_data} = result
      billing = get_in(query_data, [:data, "updatePaymentMethod", "billing"])
      assert billing["stripe_payment_method_id"] == "pm_1IgT1nEMShkCsLFnOd4GdL9I"
    end
  end

  test "fetch customer portal url", %{user: user} do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            "{\n  \"return_url\": \"https://test.tides.coloredcow.com/settings/billing\",\n  \"url\": \"https://billing.stripe.com/session/test_session_id\"\n}\n"
        }
    end)

    result = auth_query_gql_by(:customer_portal, user, variables: %{})
    assert {:ok, query_data} = result
    customerPortal = get_in(query_data, [:data, "customerPortal"])
    assert customerPortal["returnUrl"] == "https://test.tides.coloredcow.com/settings/billing"
    assert customerPortal["url"] == "https://billing.stripe.com/session/test_session_id"
  end
end
