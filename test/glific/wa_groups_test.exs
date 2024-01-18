defmodule Glific.WAGroupsTest do
  use Glific.DataCase

  alias Glific.WAGroups

  describe "wa_managed_phones" do
    alias Glific.WAGroup.WAManagedPhone

    import Glific.WAGroupsFixtures

    @invalid_attrs %{label: nil, phone: nil, is_active: nil, api_token: nil}

    test "list_wa_managed_phones/0 returns all wa_managed_phones" do
      wa_managed_phone = wa_managed_phone_fixture()
      assert WAGroups.list_wa_managed_phones() == [wa_managed_phone]
    end

    test "get_wa_managed_phone!/1 returns the wa_managed_phone with given id" do
      wa_managed_phone = wa_managed_phone_fixture()
      assert WAGroups.get_wa_managed_phone!(wa_managed_phone.id) == wa_managed_phone
    end

    test "create_wa_managed_phone/1 with valid data creates a wa_managed_phone" do
      valid_attrs = %{
        label: "some label",
        phone: "some phone",
        is_active: true,
        phone_id: "phone id 1",
        product_id: "product id 1",
        api_token: "some api_token",
        organization_id: 1,
        provider_id: 1
      }

      assert {:ok, %WAManagedPhone{} = wa_managed_phone} =
               WAGroups.create_wa_managed_phone(valid_attrs)

      assert wa_managed_phone.label == "some label"
      assert wa_managed_phone.phone == "some phone"
      assert wa_managed_phone.is_active == true
      assert wa_managed_phone.api_token == "some api_token"
    end

    test "create_wa_managed_phone/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = WAGroups.create_wa_managed_phone(@invalid_attrs)
    end

    test "update_wa_managed_phone/2 with valid data updates the wa_managed_phone" do
      wa_managed_phone = wa_managed_phone_fixture()

      update_attrs = %{
        label: "some updated label",
        phone: "some updated phone",
        is_active: false,
        api_token: "some updated api_token"
      }

      assert {:ok, %WAManagedPhone{} = wa_managed_phone} =
               WAGroups.update_wa_managed_phone(wa_managed_phone, update_attrs)

      assert wa_managed_phone.label == "some updated label"
      assert wa_managed_phone.phone == "some updated phone"
      assert wa_managed_phone.is_active == false
      assert wa_managed_phone.api_token == "some updated api_token"
    end

    test "update_wa_managed_phone/2 with invalid data returns error changeset" do
      wa_managed_phone = wa_managed_phone_fixture()

      assert {:error, %Ecto.Changeset{}} =
               WAGroups.update_wa_managed_phone(wa_managed_phone, @invalid_attrs)

      assert wa_managed_phone == WAGroups.get_wa_managed_phone!(wa_managed_phone.id)
    end

    test "delete_wa_managed_phone/1 deletes the wa_managed_phone" do
      wa_managed_phone = wa_managed_phone_fixture()
      assert {:ok, %WAManagedPhone{}} = WAGroups.delete_wa_managed_phone(wa_managed_phone)

      assert_raise Ecto.NoResultsError, fn ->
        WAGroups.get_wa_managed_phone!(wa_managed_phone.id)
      end
    end

    test "change_wa_managed_phone/1 returns a wa_managed_phone changeset" do
      wa_managed_phone = wa_managed_phone_fixture()
      assert %Ecto.Changeset{} = WAGroups.change_wa_managed_phone(wa_managed_phone)
    end
  end
end
