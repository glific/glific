defmodule Glific.WAManagedPhonesTest do
  use Glific.DataCase

  alias Glific.{
    Partners,
    WAGroup.WAManagedPhone,
    WAManagedPhones
  }

  describe "wa_managed_phones" do
    import Glific.WAManagedPhonesFixtures

    @invalid_attrs %{label: nil, phone: nil, is_active: nil, api_token: nil}

    test "list_wa_managed_phones/0 returns all wa_managed_phones", attrs do
      wa_managed_phone =
        wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

      assert WAManagedPhones.list_wa_managed_phones(%{organization_id: attrs.organization_id}) ==
               [
                 wa_managed_phone
               ]
    end

    test "get_wa_managed_phone!/1 returns the wa_managed_phone with given id", attrs do
      wa_managed_phone = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})
      assert WAManagedPhones.get_wa_managed_phone!(wa_managed_phone.id) == wa_managed_phone
    end

    test "create_wa_managed_phone/1 with valid data creates a wa_managed_phone" do
      valid_attrs = %{
        label: "some label",
        phone: "some phone",
        is_active: true,
        phone_id: 242,
        api_token: "some api_token",
        organization_id: 1,
        provider_id: 1
      }

      assert {:ok, %WAManagedPhone{} = wa_managed_phone} =
               WAManagedPhones.create_wa_managed_phone(valid_attrs)

      assert wa_managed_phone.label == "some label"
      assert wa_managed_phone.phone == "some phone"
      assert wa_managed_phone.is_active == true
      assert wa_managed_phone.api_token == "some api_token"
    end

    test "create_wa_managed_phone/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = WAManagedPhones.create_wa_managed_phone(@invalid_attrs)
    end

    test "update_wa_managed_phone/2 with valid data updates the wa_managed_phone", attrs do
      wa_managed_phone = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

      update_attrs = %{
        label: "some updated label",
        phone: "some updated phone",
        is_active: false,
        api_token: "some updated api_token"
      }

      assert {:ok, %WAManagedPhone{} = wa_managed_phone} =
               WAManagedPhones.update_wa_managed_phone(wa_managed_phone, update_attrs)

      assert wa_managed_phone.label == "some updated label"
      assert wa_managed_phone.phone == "some updated phone"
      assert wa_managed_phone.is_active == false
      assert wa_managed_phone.api_token == "some updated api_token"
    end

    test "update_wa_managed_phone/2 with invalid data returns error changeset", attrs do
      wa_managed_phone = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

      assert {:error, %Ecto.Changeset{}} =
               WAManagedPhones.update_wa_managed_phone(wa_managed_phone, @invalid_attrs)

      assert wa_managed_phone == WAManagedPhones.get_wa_managed_phone!(wa_managed_phone.id)
    end

    test "delete_wa_managed_phone/1 deletes the wa_managed_phone", attrs do
      wa_managed_phone = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})
      assert {:ok, %WAManagedPhone{}} = WAManagedPhones.delete_wa_managed_phone(wa_managed_phone)

      assert_raise Ecto.NoResultsError, fn ->
        WAManagedPhones.get_wa_managed_phone!(wa_managed_phone.id)
      end
    end

    test "change_wa_managed_phone/1 returns a wa_managed_phone changeset", attrs do
      wa_managed_phone = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})
      assert %Ecto.Changeset{} = WAManagedPhones.change_wa_managed_phone(wa_managed_phone)
    end

    test "list_wa_groups/1 fetch groups using Maytapi API", attrs do
      Partners.create_credential(%{
        organization_id: attrs.organization_id,
        shortcode: "maytapi",
        keys: %{},
        secrets: %{
          "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
          "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
        },
        is_active: true
      })

      Tesla.Mock.mock(fn _env ->
        %Tesla.Env{
          status: 200,
          body:
            "[{\"id\":43090,\"number\":\"918979120220\",\"status\":\"active\",\"type\":\"whatsapp\",\"name\":\"\",\"data\":{},\"multi_device\":true}]"
        }
      end)

      WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)
      assert :ok == WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)
    end
  end
end
