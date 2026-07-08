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

    test "fetch_by_phone/1 returns the wa_managed_phone matching the phone", attrs do
      wa_managed_phone = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

      assert {:ok, fetched} = WAManagedPhones.fetch_by_phone(wa_managed_phone.phone)
      assert fetched.id == wa_managed_phone.id
    end

    test "fetch_by_phone/1 returns an error when no managed phone matches" do
      assert {:error, _} = WAManagedPhones.fetch_by_phone("919999999999")
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

    test "fetch_wa_managed_phones/1 updates an existing phone's status in place instead of duplicating it",
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

      # first sync: the phone comes in active and a row is created
      Tesla.Mock.mock(fn _env ->
        %Tesla.Env{
          status: 200,
          body:
            ~s([{"id":43090,"number":"918979120220","status":"active","type":"whatsapp","name":""}])
        }
      end)

      assert :ok == WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)
      assert {:ok, created} = WAManagedPhones.fetch_by_phone("918979120220")
      assert created.status == "active"

      # second sync: the same phone is now loading, alongside a new active phone
      Tesla.Mock.mock(fn _env ->
        %Tesla.Env{
          status: 200,
          body:
            ~s([{"id":43090,"number":"918979120220","status":"loading","type":"whatsapp","name":""},{"id":43091,"number":"918888888888","status":"active","type":"whatsapp","name":""}])
        }
      end)

      assert :ok == WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)

      # existing row updated in place (same id, new status), new phone created
      assert {:ok, updated} = WAManagedPhones.fetch_by_phone("918979120220")
      assert updated.id == created.id
      assert updated.status == "loading"
      assert {:ok, _new_phone} = WAManagedPhones.fetch_by_phone("918888888888")
    end

    test "fetch_wa_managed_phones/1 refreshes a logged-out phone's status (id + status, no number)",
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

      existing = wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

      # Maytapi reports the phone as logged out: only its id + status, no number.
      Tesla.Mock.mock(fn _env ->
        %Tesla.Env{
          status: 200,
          body: ~s([{"id":#{existing.phone_id},"status":"disabled","type":"whatsapp"}])
        }
      end)

      # no active phone in the payload → the overall no-active error is returned,
      # but the logged-out phone's status is still refreshed
      assert {:error, "No active phones available"} ==
               WAManagedPhones.fetch_wa_managed_phones(attrs.organization_id)

      assert WAManagedPhones.get_wa_managed_phone(existing.phone_id).status == "disabled"
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

  test "status/2 raises a critical alert on a transition into a disconnected state and stamps the check time",
       %{
         organization_id: organization_id
       } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    new_status = "qr-screen"
    phone_id = wa_managed_phone.phone_id

    {:ok, updated_phone} = WAManagedPhones.status(new_status, phone_id)
    assert updated_phone.last_status_checked_at != nil

    {:ok, notification} = Repo.fetch_by(Notification, %{organization_id: organization_id})

    assert notification.message ==
             "WhatsApp phone 9829627508 is not working (status: qr-screen). Messaging is blocked — reconnect it from the WhatsApp Phones page; if it stays down it may need action on the WhatsApp/Meta side."

    # any unhealthy status blocks messaging, so it alerts as critical
    assert notification.severity == "Critical"
  end

  test "status/2 does not re-notify when the phone stays in the same bad state", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    {:ok, _} = WAManagedPhones.status("qr-screen", wa_managed_phone.phone_id)
    {:ok, _} = WAManagedPhones.status("qr-screen", wa_managed_phone.phone_id)

    # only the transition into the bad state alerts, not every repeat
    # (Repo auto-scopes to the org in context)
    assert length(Repo.all(Notification)) == 1
  end

  test "status/2 raises a critical alert when the phone is suspended by WhatsApp", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    {:ok, _} = WAManagedPhones.status("banned", wa_managed_phone.phone_id)

    {:ok, notification} = Repo.fetch_by(Notification, %{organization_id: organization_id})
    assert notification.severity == "Critical"
    assert notification.message =~ "Messaging is blocked"
  end

  test "reconcile_wa_managed_phone_statuses/1 polls Maytapi and alerts on transitions", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{"product_id" => "prod-123", "token" => "tok-123"},
      is_active: true
    })

    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body:
          ~s([{"id":#{wa_managed_phone.phone_id},"number":"9829627508","status":"disconnected"}])
      }
    end)

    assert :ok == WAManagedPhones.reconcile_wa_managed_phone_statuses(organization_id)

    assert WAManagedPhones.get_wa_managed_phone(wa_managed_phone.phone_id).status ==
             "disconnected"

    {:ok, notification} = Repo.fetch_by(Notification, %{organization_id: organization_id})
    assert notification.severity == "Critical"
  end

  test "reconcile_wa_managed_phone_statuses/1 does not touch another org's phones", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    {:ok, _} = WAManagedPhones.update_wa_managed_phone(wa_managed_phone, %{status: "active"})

    other_org = Fixtures.organization_fixture()

    Partners.create_credential(%{
      organization_id: other_org.id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{"product_id" => "prod-999", "token" => "tok-999"},
      is_active: true
    })

    # the other org's Maytapi reports the SAME phone_id as disconnected
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 200,
        body: ~s([{"id":#{wa_managed_phone.phone_id},"number":"9829627508","status":"disabled"}])
      }
    end)

    Repo.put_organization_id(other_org.id)
    assert :ok == WAManagedPhones.reconcile_wa_managed_phone_statuses(other_org.id)
    Repo.put_organization_id(organization_id)

    # org 1's phone is untouched — the other org can't reconcile it
    assert WAManagedPhones.get_wa_managed_phone(wa_managed_phone.phone_id).status == "active"
  end

  test "fetch_phone_screen/2 returns the QR payload for an admin", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{"product_id" => "prod-123", "token" => "tok-123"},
      is_active: true
    })

    # Maytapi returns the screen as raw PNG bytes (the leading bytes are the PNG
    # magic number); we hand back a base64 data-url.
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{status: 200, body: <<137, 80, 78, 71, 13, 10, 26, 10>>}
    end)

    assert {:ok, %{code: code, expires_at: %DateTime{}}} =
             WAManagedPhones.fetch_phone_screen(organization_id, wa_managed_phone.id)

    assert String.starts_with?(code, "data:image/png;base64,")
  end

  test "fetch_phone_screen/2 surfaces a Maytapi failure", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})

    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{"product_id" => "prod-123", "token" => "tok-123"},
      is_active: true
    })

    # Maytapi signals real errors as HTTP 200 + {"success": false} JSON, not a
    # PNG — the message is surfaced instead of a bogus QR image.
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{status: 200, body: ~s({"success":false,"message":"Phone is not connected"})}
    end)

    assert {:error, "Phone is not connected"} =
             WAManagedPhones.fetch_phone_screen(organization_id, wa_managed_phone.id)
  end

  test "reconnect_wa_managed_phone/2 logs the phone out to trigger a fresh QR", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})
    # a disconnected (non-healthy) phone is the reconnectable case
    {:ok, wa_managed_phone} =
      WAManagedPhones.update_wa_managed_phone(wa_managed_phone, %{status: "qr-screen"})

    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{"product_id" => "prod-123", "token" => "tok-123"},
      is_active: true
    })

    Tesla.Mock.mock(fn _env -> %Tesla.Env{status: 200, body: ~s({"success":true})} end)

    assert {:ok, %WAManagedPhone{id: id}} =
             WAManagedPhones.reconnect_wa_managed_phone(organization_id, wa_managed_phone.id)

    assert id == wa_managed_phone.id
  end

  test "reconnect_wa_managed_phone/2 refuses to log out a phone that is already active", %{
    organization_id: organization_id
  } do
    wa_managed_phone = Fixtures.wa_managed_phone_fixture(%{organization_id: organization_id})
    {:ok, _} = WAManagedPhones.update_wa_managed_phone(wa_managed_phone, %{status: "active"})

    assert {:error, message} =
             WAManagedPhones.reconnect_wa_managed_phone(organization_id, wa_managed_phone.id)

    assert message =~ "already connected"
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
