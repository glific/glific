defmodule Glific.Groups.WAGroupsTest do
  use Glific.DataCase, async: false
  use ExUnit.Case

  alias Glific.{
    Groups.WAGroup,
    Groups.WAGroups,
    Partners,
    Seeds.SeedsDev,
    WAManagedPhonesFixtures
  }

  setup do
    organization = SeedsDev.seed_organizations()
    WAManagedPhonesFixtures.wa_managed_phone_fixture(%{organization_id: organization.id})

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

  test "fetch_wa_managed_phones/1 fetch whatsapp linked phones to maytapi account", attrs do
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
end
