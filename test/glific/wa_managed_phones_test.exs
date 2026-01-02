defmodule Glific.WAManagedPhonesTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Fixtures,
    Notifications.Notification,
    Partners,
    Repo,
    WAGroup.WAManagedPhone,
    WAManagedPhones
  }

  alias GlificWeb.Providers.Maytapi.Controllers.StatusController

  describe "wa_managed_phones" do
    import Glific.Fixtures

    @invalid_attrs %{label: nil, phone: nil}

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
        phone_id: 242,
        product_id: "5a441f2-f033-40f4-8a6sd34ns-a8sr58",
        organization_id: 1,
        provider_id: 1,
        contact_id: 1
      }

      assert {:ok, %WAManagedPhone{} = wa_managed_phone} =
               WAManagedPhones.create_wa_managed_phone(valid_attrs)

      assert wa_managed_phone.label == "some label"
      assert wa_managed_phone.phone == "some phone"
      assert wa_managed_phone.product_id == "5a441f2-f033-40f4-8a6sd34ns-a8sr58"
    end

    test "create_wa_managed_phone/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = WAManagedPhones.create_wa_managed_phone(@invalid_attrs)
    end

    test "update_wa_managed_phone/2 with valid data updates the wa_managed_phone", attrs do
      wa_managed_phone = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

      update_attrs = %{
        label: "some updated label",
        phone: "some updated phone"
      }

      assert {:ok, %WAManagedPhone{} = wa_managed_phone} =
               WAManagedPhones.update_wa_managed_phone(wa_managed_phone, update_attrs)

      assert wa_managed_phone.label == "some updated label"
      assert wa_managed_phone.phone == "some updated phone"
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

    test "fetch_wa_managed_phones/1  fetch whatsapp linked phones to maytapi account", attrs do
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

      assert :ok == WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)
    end

    test "fetch_wa_managed_phones/1  fetch whatsapp linked phones to maytapi account and should raise error if the number is inactive",
         attrs do
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
            "[{\"id\":43090,\"number\":\"918979120220\",\"status\":\"disabled\",\"type\":\"whatsapp\",\"name\":\"\",\"data\":{},\"multi_device\":true}]"
        }
      end)

      assert {:error, "No active phones available"} ==
               WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)
    end

    test "fetch_wa_managed_phones/1 should raise error when the credentials are invalid",
         attrs do
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
            "{\"success\":false,\"message\":\"Product id is wrong! Please check your Account information.\"}"
        }
      end)

      assert {:error, "Product id is wrong! Please check your Account information."} ==
               WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)
    end
  end

  test "status/2 webhook should update the status on wa_managed_phone", %{
    staff: user,
    conn: conn
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: user.organization_id})

    params = %{
      "phoneId" => wa_managed_phone.phone_id,
      "phone_id" => wa_managed_phone.phone_id,
      "pid" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d",
      "product_id" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d",
      "status" => "active",
      "type" => "status"
    }

    conn = StatusController.status(conn, params)

    assert conn.status == 200
  end

  test "status/2 should update the status on wa_managed_phone check all the possible errors", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    new_status = "active"
    phone_id = wa_managed_phone.phone_id

    {:ok, updated_phone} = WAManagedPhones.status(new_status, phone_id)

    assert updated_phone.status == new_status

    # should give an error if phone id does not exist
    new_status = "active"
    phone_id = 999

    assert WAManagedPhones.status(new_status, phone_id) == {:error, "Phone ID not found"}
  end

  test "status/2 should create a notification when status is not 'active' or loading", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    new_status = "qr-screen"
    phone_id = wa_managed_phone.phone_id

    {:ok, _updated_phone} = WAManagedPhones.status(new_status, phone_id)

    {:ok, notification} =
      Repo.fetch_by(Notification, %{
        organization_id: organization_id
      })

    assert notification.message ==
             "Cannot send messages. WhatsApp phone 9829627508 is not connected with Maytapi. Current status: qr-screen"
  end

  test "status/2 shouldn't create a notification when status is 'active' or loading", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})
    new_status = wa_managed_phone.status
    phone_id = wa_managed_phone.phone_id

    {:ok, _updated_phone} = WAManagedPhones.status(new_status, phone_id)

    fetch_result = Repo.fetch_by(Notification, %{organization_id: organization_id})

    assert fetch_result ==
             {:error, ["Elixir.Glific.Notifications.Notification", "Resource not found"]}
  end

  test "delete_existing_wa_managed_phones/1 should delete the WhatsApp data", %{
    organization_id: organization_id
  } do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    _wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    assert Repo.get_by(WAManagedPhone, %{id: wa_managed_phone.id},
             organization_id: organization_id
           )

    assert WAManagedPhones.delete_existing_wa_managed_phones(organization_id) == :ok

    refute Repo.get_by(WAManagedPhone, %{id: wa_managed_phone.id},
             organization_id: organization_id
           )
  end
end
