defmodule Glific.Groups.WhatsappMessageTest do
  use Glific.DataCase, async: false
  use ExUnit.Case
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Groups.WaGroupsCollections,
    Partners,
    Partners.Credential,
    Providers.Maytapi.Message,
    Providers.Maytapi.WAWorker,
    Seeds.SeedsDev,
    WAGroup.WAMessage
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

  defp mock_maytapi_response(status, body) do
    Tesla.Mock.mock(fn
      %Tesla.Env{
        method: :post,
        url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/242/sendMessage"
      } ->
        {:ok, %Tesla.Env{status: status, body: body}}
    end)
  end

  test "create_and_send_wa_message/3 sends a text message in a whatsapp group successfully",
       attrs do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    mock_maytapi_response(200, %{
      "success" => true,
      "data" => %{
        "chatId" => "120363238104@g.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
      }
    })

    params = %{
      wa_group_id: wa_group.id,
      message: "hi",
      wa_managed_phone_id: wa_managed_phone.id
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)
    assert wa_message.body == params.message
    assert wa_message.bsp_status == :sent
    assert wa_message.flow == :outbound
  end

  test "send_message_to_wa_group_collection/2 sends a text message in a whatsapp group collection and wa_groups in the collection",
       attrs do
    group =
      Fixtures.group_fixture(%{organization_id: attrs.organization_id, group_type: "WA"})

    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    WaGroupsCollections.create_wa_groups_collection(%{
      group_id: group.id,
      wa_group_id: wa_group.id,
      organization_id: attrs.organization_id
    })

    mock_maytapi_response(200, %{
      "success" => true,
      "data" => %{
        "chatId" => "120363238104@g.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
      }
    })

    params = %{
      group_id: group.id,
      message: "hi"
    }

    Message.send_message_to_wa_group_collection(group, params)

    [wa_group_msg, wa_group_collection_msg] =
      Glific.WAGroup.WAMessage
      |> order_by([wam], desc: wam.inserted_at)
      |> limit(2)
      |> Repo.all()

    assert wa_group_collection_msg.body == params.message
    assert wa_group_collection_msg.group_id == group.id
    assert wa_group_collection_msg.wa_group_id == nil
    assert wa_group_msg.body == params.message
    assert wa_group_msg.group_id == nil
    assert wa_group_msg.wa_group_id == wa_group.id
  end

  test "create_and_send_wa_message/3 send media message successfully",
       attrs do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    mock_maytapi_response(200, %{
      "success" => true,
      "data" => %{
        "chatId" => "120363238104@g.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
      }
    })

    # sending image
    message_media =
      Fixtures.message_media_fixture(%{
        organization_id: attrs.organization_id,
        caption: "image caption"
      })

    params = %{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_managed_phone.id,
      media_id: message_media.id,
      type: :image
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)
    assert wa_message.type == :image
    assert is_nil(wa_message.media_id) == false

    # sending audio
    message_media = Fixtures.message_media_fixture(%{organization_id: attrs.organization_id})

    params = %{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_managed_phone.id,
      media_id: message_media.id,
      type: :audio
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)

    assert wa_message.type == :audio
    assert is_nil(wa_message.media_id) == false

    # sending video
    message_media =
      Fixtures.message_media_fixture(%{
        organization_id: attrs.organization_id,
        caption: "video caption"
      })

    params = %{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_managed_phone.id,
      media_id: message_media.id,
      type: :video
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)
    assert wa_message.type == :video
    assert is_nil(wa_message.media_id) == false

    # sending document
    message_media =
      Fixtures.message_media_fixture(%{
        organization_id: attrs.organization_id,
        caption: "document caption"
      })

    params = %{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_managed_phone.id,
      media_id: message_media.id,
      type: :document
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)
    assert wa_message.type == :document
    assert is_nil(wa_message.media_id) == false

    # sending sticker
    message_media = Fixtures.message_media_fixture(%{organization_id: attrs.organization_id})

    params = %{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_managed_phone.id,
      media_id: message_media.id,
      type: :sticker
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)
    assert wa_message.type == :sticker
    assert is_nil(wa_message.media_id) == false

    # check the caption limit
    message_media =
      Fixtures.message_media_fixture(%{
        organization_id: attrs.organization_id,
        caption: Faker.Lorem.sentence(6000)
      })

    params = %{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_managed_phone.id,
      media_id: message_media.id,
      type: :image
    }

    {:error, error_message} =
      Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)

    assert error_message == "Message size greater than 6000 characters"
  end

  test "create_and_send_wa_message/2 should return error when characters limit is reached when sending text message",
       attrs do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    params = %{
      wa_group_id: wa_group.id,
      message: Faker.Lorem.sentence(6000),
      wa_managed_phone_id: wa_managed_phone.id
    }

    {:error, error_msg} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)
    assert error_msg == "Message size greater than 6000 characters"
  end

  test "receive_text/1 receive text message correctly" do
    params = %{
      "message" => %{"id" => "1", "text" => "Hello, World!", "fromMe" => false},
      "user" => %{"phone" => "1234567890", "name" => "John Doe"}
    }

    expected_result = %{
      bsp_id: "1",
      body: "Hello, World!",
      sender: %{phone: "1234567890", name: "John Doe"},
      flow: :inbound,
      status: :received
    }

    assert Message.receive_text(params) == expected_result
  end

  test "receive_media/1 received media message" do
    params = %{
      "message" => %{
        "id" => "2",
        "caption" => "A photo",
        "url" => "http://example.com/photo.jpg",
        "type" => "image",
        "fromMe" => false
      },
      "user" => %{"phone" => "1234567890", "name" => "Jane Doe"}
    }

    expected_result = %{
      bsp_id: "2",
      caption: "A photo",
      url: "http://example.com/photo.jpg",
      content_type: "image",
      source_url: "http://example.com/photo.jpg",
      sender: %{phone: "1234567890", name: "Jane Doe"},
      flow: :inbound,
      status: :received
    }

    assert Message.receive_media(params) == expected_result
  end

  test "send_message_to_wa_group_collection/2 check the possible error",
       attrs do
    group =
      Fixtures.group_fixture(%{organization_id: attrs.organization_id, group_type: "WA"})

    params = %{message: "hi", type: :text, organization_id: attrs.organization_id, media_id: nil}
    {:error, error_message} = Message.send_message_to_wa_group_collection(group, params)

    assert error_message == "Cannot send message: No WhatsApp group found in the collection"
  end

  test "create_and_send_wa_message/3 send media message successfully, even when gupshup is inactive",
       attrs do
    # clearing the org cache that's setup at the beginning of test
    Partners.remove_organization_cache(1, "glific")

    # Setting the gupshup cred active status to false, which will then not create
    # a bsp key in the organization.services map

    {1, _} =
      Credential
      |> where([c], c.organization_id == ^attrs.organization_id and c.provider_id == 1)
      |> update([c], set: [is_active: false])
      |> select([c], {c.provider_id})
      |> Repo.update_all([])

    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    mock_maytapi_response(
      200,
      "{\"success\": true, \"data\": {\"chatId\": \"120363238104@g.us\", \"msgId\": \"a3ff8460-c710-11ee-a8e7-5fbaaf152c1d\"}}"
    )

    # sending image
    message_media =
      Fixtures.message_media_fixture(%{
        organization_id: attrs.organization_id,
        caption: "image caption"
      })

    params = %{
      wa_group_id: wa_group.id,
      wa_managed_phone_id: wa_managed_phone.id,
      media_id: message_media.id,
      type: :image
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)

    assert_enqueued(worker: WAWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :wa_group, with_scheduled: true, with_safety: false)

    assert wa_message.type == :image
  end

  test "Handling create_and_send_wa_message/3 failure",
       attrs do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    Tesla.Mock.mock(fn
      %Tesla.Env{
        method: :post
      } ->
        {:error, :timeout}
    end)

    params = %{
      wa_group_id: wa_group.id,
      message: "hi",
      wa_managed_phone_id: wa_managed_phone.id
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)

    assert_enqueued(worker: WAWorker, prefix: "global")

    assert %{success: 0, failure: 1, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :wa_group, with_scheduled: true, with_safety: false)

    wa_message =
      WAMessage
      |> where([wa], wa.id == ^wa_message.id)
      |> Repo.one()

    assert String.contains?(wa_message.errors["message"], ":timeout")
  end

  test "Handling create_and_send_wa_message/3 4xx failure",
       attrs do
    wa_managed_phone =
      Fixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    mock_maytapi_response(
      400,
      "{\"success\": false, \"message\": \"You dont own the phone\"}"
    )

    params = %{
      wa_group_id: wa_group.id,
      message: "hi",
      wa_managed_phone_id: wa_managed_phone.id
    }

    {:ok, wa_message} = Message.create_and_send_wa_message(wa_managed_phone, wa_group, params)

    assert_enqueued(worker: WAWorker, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :wa_group, with_scheduled: true, with_safety: false)

    wa_message =
      WAMessage
      |> where([wa], wa.id == ^wa_message.id)
      |> Repo.one()

    assert wa_message.bsp_status == :error
    assert String.contains?(wa_message.errors["message"], "You dont own the phone")
  end
end
