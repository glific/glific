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


  test "create a billing and test possible scenarios and errors", %{user: user} do
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
end
