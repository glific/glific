defmodule Glific.Providers.Maytapi.WAWorkerTest do
  use Glific.DataCase, async: false

  alias Glific.{
    Fixtures,
    Groups.WAGroup,
    Partners,
    Providers.Maytapi.WAWorker,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    Fixtures.wa_managed_phone_fixture(%{organization_id: organization.id})

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

    %{organization_id: organization.id}
  end

  @active_phones ~s([{"id":242,"number":"9829627508","status":"active","type":"whatsapp","name":""}])
  @groups_body ~s({"count":1,"data":[{"admins":["917834811115@c.us"],"config":{"disappear":false,"edit":"all","send":"all"},"id":"120363213149844251@g.us","name":"Expenses","participants":["917834811115@c.us"]}],"limit":500,"success":true,"total":1})

  describe "perform_periodic/1" do
    test "syncs groups and returns :ok on success (contact_sync succeeds)",
         %{organization_id: organization_id} do
      Tesla.Mock.mock(fn
        %{url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/listPhones"} ->
          %Tesla.Env{status: 200, body: @active_phones}

        _env ->
          %Tesla.Env{status: 200, body: @groups_body}
      end)

      assert :ok = WAWorker.perform_periodic(organization_id)
      assert {:ok, _group} = Repo.fetch_by(WAGroup, %{label: "Expenses"})
    end

    test "returns :ok without crashing when the sync can't reach maytapi (contact_sync fails)",
         %{organization_id: organization_id} do
      # listPhones reports failure, so fetch_wa_managed_phones -> sync_wa_groups
      # returns {:error, _}. The cron must still complete cleanly — the failure
      # is surfaced via the contact_sync action counter, not a raised error.
      Tesla.Mock.mock(fn _env ->
        %Tesla.Env{status: 200, body: ~s({"success":false,"message":"instance not found"})}
      end)

      assert :ok = WAWorker.perform_periodic(organization_id)
      assert {:error, _reason} = Repo.fetch_by(WAGroup, %{label: "Expenses"})
    end
  end
end
