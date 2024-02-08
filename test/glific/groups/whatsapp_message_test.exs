defmodule Glific.Groups.WhatsappMessageTest do
  use Glific.DataCase, async: false
  use ExUnit.Case

  alias Glific.Providers.Maytapi.Message

  alias Glific.{
    Partners,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "maytapi",
      keys: %{},
      secrets: %{
        "phone" => "917834811114",
        "phone_id" => "42093",
        "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
        "token" => "f4f38e00-3a50-4892-99ce-a282fe24d041"
      },
      is_active: true
    })

    Tesla.Mock.mock(fn
      %{
        method: :post,
        url: "https://api.maytapi.com/api/3fa22108-f464-41e5-81d9-d8a298854430/42093/sendMessage"
      } ->
        %Tesla.Env{
          status: 200,
          body: "{\"data\": \"Message sent successfully\"}"
        }
    end)

    :ok
  end

  test "sends a text message and receives status", attrs do
    params = %{phone: "8979627508", message: "hi"}

    result = Message.send_text(attrs.organization_id, params)
    assert {:ok, %Tesla.Env{status: 200, body: response_body}} = result
    assert response_body == "{\"data\": \"Message sent successfully\"}"
  end

  test "processes received text message correctly" do
    params = %{
      "message" => %{"id" => "1", "text" => "Hello, World!"},
      "user" => %{"phone" => "1234567890", "name" => "John Doe"}
    }

    expected_result = %{
      bsp_message_id: "1",
      body: "Hello, World!",
      sender: %{phone: "1234567890", name: "John Doe"}
    }

    assert Message.receive_text(params) == expected_result
  end

  test "processes received media message correctly" do
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
      bsp_message_id: "2",
      caption: "A photo",
      url: "http://example.com/photo.jpg",
      content_type: "image",
      source_url: "http://example.com/photo.jpg",
      sender: %{phone: "1234567890", name: "Jane Doe"}
    }

    assert Message.receive_media(params) == expected_result
  end
end
