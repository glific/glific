defmodule Glific.Groups.WhatsappMessageTest do
  use Glific.DataCase, async: false
  use ExUnit.Case

  alias Glific.{
    Partners,
    Providers.Maytapi.Message,
    Seeds.SeedsDev,
    Seeds.SeedsDev,
    WAManagedPhonesFixtures
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
        url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/42093/sendMessage"
      } ->
        {:ok, %Tesla.Env{status: status, body: body}}
    end)
  end

  test "create_and_send_wa_message/3 sends a text message in a whatsapp group successfully",
       attrs do
    wa_managed_phone =
      WAManagedPhonesFixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      WAManagedPhonesFixtures.wa_group_fixture(%{
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

    user = attrs |> Map.put(:name, "NGO user")

    params = %{
      wa_group_id: wa_group.id,
      message: "hi",
      wa_managed_phone_id: wa_managed_phone.id
    }

    {:ok, response} = Message.create_and_send_wa_message(user, params)
    message = response.args["message"]
    assert message["body"] == params.message
    assert message["bsp_status"] == "sent"
  end

  test "create_and_send_wa_message/2 should return error when characters limit is reached when sending text message",
       attrs do
    wa_managed_phone =
      WAManagedPhonesFixtures.wa_managed_phone_fixture(%{organization_id: attrs.organization_id})

    wa_group =
      WAManagedPhonesFixtures.wa_group_fixture(%{
        organization_id: attrs.organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    user = attrs |> Map.put(:name, "NGO user")

    params = %{
      wa_group_id: wa_group.id,
      message: Faker.Lorem.sentence(6000),
      wa_managed_phone_id: wa_managed_phone.id
    }

    {:error, error_msg} = Message.create_and_send_wa_message(user, params)
    assert error_msg == "Message size greater than 6000 characters"
  end

  test "receive_text/1 receive text message correctly" do
    params = %{
      "message" => %{"id" => "1", "text" => "Hello, World!"},
      "user" => %{"phone" => "1234567890", "name" => "John Doe"}
    }

    expected_result = %{
      bsp_id: "1",
      body: "Hello, World!",
      sender: %{phone: "1234567890", name: "John Doe"}
    }

    assert Message.receive_text(params) == expected_result
  end

  test "receive_media/1 received media message" do
    params = %{
      "message" => %{
        "id" => "2",
        "caption" => "A photo",
        "url" => "http://example.com/photo.jpg",
        "type" => "image"
      },
      "user" => %{"phone" => "1234567890", "name" => "Jane Doe"}
    }

    expected_result = %{
      bsp_id: "2",
      caption: "A photo",
      url: "http://example.com/photo.jpg",
      content_type: "image",
      source_url: "http://example.com/photo.jpg",
      sender: %{phone: "1234567890", name: "Jane Doe"}
    }

    assert Message.receive_media(params) == expected_result
  end
end
