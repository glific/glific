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
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/billings/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/billings/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/billings/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/billings/create.gql")
  load_gql(:create_subscription, GlificWeb.Schema, "assets/gql/billings/create_subscription.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/billings/update.gql")
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
    {:ok, billing} = Repo.fetch_by(Billing, %{name: name, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:update, user,
        variables: %{
          "id" => billing.id,
          "input" => %{
            "currency" => "usd"
          }
        }
      )

    assert {:ok, query_data} = result
    currency = get_in(query_data, [:data, "updateBilling", "billing", "currency"])
    assert currency == "usd"
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
end
