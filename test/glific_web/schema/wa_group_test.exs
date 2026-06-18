defmodule GlificWeb.Schema.WaGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  import Ecto.Query

  setup do
    organization = SeedsDev.seed_organizations()

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
        "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
      },
      is_active: true
    })

    :ok
  end

  load_gql(:create, GlificWeb.Schema, "assets/gql/wa_groups/create.gql")
  load_gql(:update, GlificWeb.Schema, "assets/gql/wa_groups/update.gql")

  describe "createWaGroup" do
    test "provisions a wa_group via Maytapi and seeds an is_primary membership for the creator",
         %{user: user} do
      wa_phone =
        Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

      Tesla.Mock.mock(fn
        %{
          method: :post,
          url:
            "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/" <>
                _phone_id_and_endpoint
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body:
               Jason.encode!(%{
                 "success" => true,
                 "data" => %{"id" => "120363999111111111@g.us"}
               })
           }}
      end)

      result =
        auth_query_gql_by(:create, user,
          variables: %{
            "input" => %{
              "name" => "Created via Glific",
              "waManagedPhoneId" => to_string(wa_phone.id),
              "numbers" => ["918888888888"]
            }
          }
        )

      assert {:ok, query_data} = result
      wa_group = get_in(query_data, [:data, "createWaGroup", "waGroup"])
      assert wa_group["label"] == "Created via Glific"
      assert wa_group["bspId"] == "120363999111111111@g.us"

      # DB side-effects: wa_groups row exists, primary membership for creator
      assert {:ok, persisted} =
               Repo.fetch_by(WAGroup, %{bsp_id: "120363999111111111@g.us"})

      assert persisted.label == "Created via Glific"

      assert %WAGroupPhone{is_primary: true, is_active: true} =
               Repo.get_by!(WAGroupPhone, %{
                 wa_group_id: persisted.id,
                 wa_managed_phone_id: wa_phone.id
               })
    end

    test "persists the members from the Maytapi response into contacts_wa_groups",
         %{user: user} do
      wa_phone =
        Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body:
             Jason.encode!(%{
               "success" => true,
               "data" => %{
                 "id" => "120363428775624359@g.us",
                 "name" => "Group Title",
                 "participants" => ["919425010449@c.us", "918657048984@c.us"],
                 "admins" => ["918657048984@c.us"]
               }
             })
         }}
      end)

      result =
        auth_query_gql_by(:create, user,
          variables: %{
            "input" => %{
              "name" => "Group Title",
              "waManagedPhoneId" => to_string(wa_phone.id),
              "numbers" => ["919425010449"]
            }
          }
        )

      assert {:ok, _query_data} = result

      assert {:ok, persisted} =
               Repo.fetch_by(WAGroup, %{bsp_id: "120363428775624359@g.us"})

      # Both participants from the response are now members of the group.
      member_count =
        ContactWAGroup
        |> where([cwg], cwg.wa_group_id == ^persisted.id)
        |> Repo.aggregate(:count)

      assert member_count == 2

      # The admin from the response is flagged is_admin: true.
      admin_contact =
        Repo.get_by!(Glific.Contacts.Contact, %{
          phone: "918657048984",
          organization_id: user.organization_id
        })

      assert %ContactWAGroup{is_admin: true} =
               Repo.get_by!(ContactWAGroup, %{
                 wa_group_id: persisted.id,
                 contact_id: admin_contact.id
               })
    end

    test "surfaces Maytapi non-2xx as a GraphQL error and does not insert a wa_group",
         %{user: user} do
      wa_phone =
        Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok,
         %Tesla.Env{
           status: 400,
           body: Jason.encode!(%{"success" => false, "message" => "phone not connected"})
         }}
      end)

      result =
        auth_query_gql_by(:create, user,
          variables: %{
            "input" => %{
              "name" => "Should not persist",
              "waManagedPhoneId" => to_string(wa_phone.id),
              "numbers" => ["918888888888"]
            }
          }
        )

      assert {:ok, query_data} = result
      refute is_nil(query_data[:errors])

      # No wa_groups row created.
      assert is_nil(Repo.get_by(WAGroup, label: "Should not persist"))
    end
  end

  describe "updateWaGroup" do
    test "renames an existing wa_group via Maytapi and updates the local label",
         %{user: user} do
      wa_phone =
        Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: user.organization_id,
          wa_managed_phone_id: wa_phone.id,
          label: "Old name"
        })

      # The acting phone is resolved server-side: it must be a managed phone
      # whose contact is a group admin.
      {:ok, _} =
        ContactWAGroups.create_contact_wa_group(%{
          contact_id: wa_phone.contact_id,
          wa_group_id: wa_group.id,
          organization_id: user.organization_id,
          is_admin: true
        })

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}
      end)

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "id" => to_string(wa_group.id),
              "name" => "New name"
            }
          }
        )

      assert {:ok, query_data} = result
      returned = get_in(query_data, [:data, "updateWaGroup", "waGroup"])
      assert returned["label"] == "New name"

      assert Repo.reload!(wa_group).label == "New name"
    end

    test "adds and removes members via Maytapi in a single call", %{user: user} do
      org_id = user.organization_id
      wa_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: wa_phone.id
        })

      contact_to_add = Fixtures.contact_fixture(%{organization_id: org_id})
      contact_to_remove = Fixtures.contact_fixture(%{organization_id: org_id})

      # The acting phone must be a group admin to add/remove participants.
      {:ok, _} =
        ContactWAGroups.create_contact_wa_group(%{
          contact_id: wa_phone.contact_id,
          wa_group_id: wa_group.id,
          organization_id: org_id,
          is_admin: true
        })

      # Pre-existing membership for the contact we will remove.
      {:ok, _} =
        ContactWAGroups.create_contact_wa_group(%{
          contact_id: contact_to_remove.id,
          wa_group_id: wa_group.id,
          organization_id: org_id
        })

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}
      end)

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "id" => to_string(wa_group.id),
              "addContactIds" => [to_string(contact_to_add.id)],
              "removeContactId" => to_string(contact_to_remove.id)
            }
          }
        )

      assert {:ok, query_data} = result

      assert get_in(query_data, [:data, "updateWaGroup", "waGroup", "id"]) ==
               to_string(wa_group.id)

      member_ids =
        ContactWAGroup
        |> where([c], c.wa_group_id == ^wa_group.id)
        |> select([c], c.contact_id)
        |> Repo.all()

      assert contact_to_add.id in member_ids
      refute contact_to_remove.id in member_ids
    end

    test "returns an error when no managed phone is a group admin", %{user: user} do
      org_id = user.organization_id
      wa_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: org_id})

      wa_group =
        Fixtures.wa_group_fixture(%{
          organization_id: org_id,
          wa_managed_phone_id: wa_phone.id
        })

      # The managed phone's contact is a member but NOT an admin, so no acting
      # phone can be resolved.
      {:ok, _} =
        ContactWAGroups.create_contact_wa_group(%{
          contact_id: wa_phone.contact_id,
          wa_group_id: wa_group.id,
          organization_id: org_id,
          is_admin: false
        })

      result =
        auth_query_gql_by(:update, user,
          variables: %{
            "input" => %{
              "id" => to_string(wa_group.id),
              "name" => "New name"
            }
          }
        )

      assert {:ok, query_data} = result
      refute is_nil(query_data[:errors])
      assert Repo.reload!(wa_group).label != "New name"
    end
  end
end
