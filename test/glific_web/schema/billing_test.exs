defmodule GlificWeb.Schema.BillingTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Partners.Billing,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_billing(organization)
    :ok
  end

  load_gql(:count, GlificWeb.Schema, "assets/gql/billings/count.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/billings/list.gql")
  load_gql(:by_id, GlificWeb.Schema, "assets/gql/billings/by_id.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/billings/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/billings/update.gql")
  load_gql(:delete, GlificWeb.Schema, "assets/gql/billings/delete.gql")

  test "create a billing", %{user: user} do
    name = "Billing name"
    {:ok, _billing} = Repo.fetch_by(Billing, %{name: name, organization_id: user.organization_id})

    result =
      auth_query_gql_by(:create, user,
        variables: %{
          "input" => %{
            "name" => "Billing user",
            "email" => "billing@gmail.com",
            "currency" => "inr"
          }
        }
      )

    assert {:ok, query_data} = result
    label = get_in(query_data, [:data, "createBilling", "billing", "email"])
    assert label == "billing@gmail.com"
  end

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
end
