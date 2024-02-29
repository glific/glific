defmodule GlificWeb.Schema.ContactWaGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Contacts,
    Fixtures,
    WAManagedPhonesFixtures,
    Seeds.SeedsDev
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/contact_wa_groups/create.gql")
  load_gql(:list, GlificWeb.Schema, "assets/gql/contact_wa_groups/list.gql")
  load_gql(:sync, GlificWeb.Schema, "assets/gql/contact_wa_groups/sync.gql")

  load_gql(
    :update_wa_group,
    GlificWeb.Schema,
    "assets/gql/contact_wa_groups/update_wa_group.gql"
  )

  test "update group contacts", %{user: user_auth} = attrs do
    user = Fixtures.user_fixture()

    wa_managed_phone =
      WAManagedPhonesFixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      WAManagedPhonesFixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    [contact1, contact2 | _] =
      Contacts.list_contacts(%{filter: %{organization_id: user.organization_id}})

    # add wa_group contacts
    result =
      auth_query_gql_by(:update_wa_group, user_auth,
        variables: %{
          "input" => %{
            "wa_group_id" => wa_group.id,
            "add_wa_contact_ids" => [contact1.id, contact2.id],
            "delete_wa_contact_ids" => []
          }
        }
      )

    assert {:ok, query_data} = result
    IO.inspect(query_data)
  end
end
