defmodule Glific.Groups.WAGroupsTest do
  use Glific.DataCase, async: false
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Groups.WAGroup,
    Groups.WAGroups,
    Partners,
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

    :ok
  end

  test "fetch_wa_groups/1 fetch groups using Maytapi API", attrs do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"Expenses\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"Movie Plan\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\",\"name\":\"Developer Group\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
      }
    end)

    assert :ok == WAGroups.fetch_wa_groups(attrs.organization_id)

    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Expenses"})
    assert group.label == "Expenses"
    assert group.bsp_id == "120363213149844251@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Movie Plan"})
    assert group.label == "Movie Plan"
    assert group.bsp_id == "120363203450035277@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Developer Group"})
    assert group.label == "Developer Group"
    assert group.bsp_id == "120363218884368888@g.us"

    # when we try to enter redundant groups again.
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"Expenses\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"Movie Plan\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368889@g.us\",\"name\":\"Movie PlanB\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\", \"name\":\"Developer Group\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
      }
    end)

    assert :ok == WAGroups.fetch_wa_groups(attrs.organization_id)
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Expenses"})
    assert group.label == "Expenses"
    assert group.bsp_id == "120363213149844251@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Movie Plan"})
    assert group.label == "Movie Plan"
    assert group.bsp_id == "120363203450035277@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Developer Group"})
    assert group.label == "Developer Group"
    assert group.bsp_id == "120363218884368888@g.us"
    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "Movie PlanB"})
    assert group.label == "Movie PlanB"
    assert group.bsp_id == "120363218884368889@g.us"
  end

  test "setting maytapi webhook endpoint, success", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "pid" => "dc01968f-####-####-####-7cfcf51aa423",
            "webhook" => "https://myserver.com/send/callback/here",
            "ack_delivery" => true,
            "phone_limit" => 2
          }
        }
    end)

    assert :ok =
             WAGroups.set_webhook_endpoint(%{
               id: attrs.organization_id,
               shortcode: "maytapi"
             })
  end

  test "setting maytapi webhook endpoint, failed", attrs do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 400,
          body: %{
            "message" => "error"
          }
        }
    end)

    assert {:error, _} =
             WAGroups.set_webhook_endpoint(%{
               id: attrs.organization_id,
               shortcode: "maytapi"
             })
  end

  test "fetch_wa_groups/1 fetch groups for empty group label", attrs do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          "{\"count\":79,\"data\":[{\"admins\":[\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363213149844251@g.us\",\"name\":\"marketing\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\",\"917834811115@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363203450035277@g.us\",\"name\":\"admin group\",\"participants\":[\"917834811116@c.us\",\"917834811115@c.us\",\"917834811114@c.us\"]},{\"admins\":[\"917834811114@c.us\"],\"config\":{\"disappear\":false,\"edit\":\"all\",\"send\":\"all\"},\"id\":\"120363218884368888@g.us\",\"name\":\"\",\"participants\":[\"917834811114@c.us\"]}],\"limit\":500,\"success\":true,\"total\":79}"
      }
    end)

    assert :ok == WAGroups.fetch_wa_groups(attrs.organization_id)

    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "marketing"})
    assert group.label == "marketing"
    assert group.bsp_id == "120363213149844251@g.us"

    assert {:ok, group} = Repo.fetch_by(WAGroup, %{label: "admin group"})
    assert group.label == "admin group"
    assert group.bsp_id == "120363203450035277@g.us"

    # group with an empty name is not created
    assert is_nil(Repo.get_by(WAGroup, label: ""))
  end

  describe "maybe_create_group/1" do
    test "creates a new group when it doesn't exist", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "New Group",
        bsp_id: "120363299999999999@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      assert {:ok, wa_group} = WAGroups.maybe_create_group(params)
      assert wa_group.label == "New Group"
      assert wa_group.bsp_id == "120363299999999999@g.us"
    end

    test "returns existing group when label matches", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "Existing Group",
        bsp_id: "120363288888888888@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      {:ok, original} = WAGroups.maybe_create_group(params)
      {:ok, found} = WAGroups.maybe_create_group(params)

      assert original.id == found.id
      assert found.label == "Existing Group"
    end

    test "updates label when existing group has a different label", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "Old Label",
        bsp_id: "120363277777777777@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      {:ok, original} = WAGroups.maybe_create_group(params)
      assert original.label == "Old Label"

      updated_params = %{params | label: "New Label"}
      {:ok, updated} = WAGroups.maybe_create_group(updated_params)

      assert updated.id == original.id
      assert updated.label == "New Label"
    end

    test "returns existing group without updating when label is nil", attrs do
      wa_managed_phone = Fixtures.get_wa_managed_phone(attrs.organization_id)

      params = %{
        label: "Keep This Label",
        bsp_id: "120363266666666666@g.us",
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      }

      {:ok, original} = WAGroups.maybe_create_group(params)
      assert original.label == "Keep This Label"

      nil_label_params = %{params | label: nil}
      {:ok, result} = WAGroups.maybe_create_group(nil_label_params)

      assert result.id == original.id
      assert result.label == "Keep This Label"
    end
  end
end
