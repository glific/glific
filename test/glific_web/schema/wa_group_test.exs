defmodule GlificWeb.Schema.WaGroupTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

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
  load_gql(:update_subject, GlificWeb.Schema, "assets/gql/wa_groups/update_subject.gql")

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

  describe "updateWaGroupSubject" do
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

      Tesla.Mock.mock(fn %{method: :post} ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}
      end)

      result =
        auth_query_gql_by(:update_subject, user,
          variables: %{
            "id" => to_string(wa_group.id),
            "waManagedPhoneId" => to_string(wa_phone.id),
            "subject" => "New name"
          }
        )

      assert {:ok, query_data} = result
      returned = get_in(query_data, [:data, "updateWaGroupSubject", "waGroup"])
      assert returned["label"] == "New name"

      assert Repo.reload!(wa_group).label == "New name"
    end
  end
end
