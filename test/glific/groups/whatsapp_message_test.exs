defmodule Glific.Groups.WhatsappMessageTest do
  use Glific.DataCase, async: false
  use ExUnit.Case

  alias Glific.{
    Partners,
    Providers.Maytapi.Message,
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

  test "send_text/2 sends a text message successfully", attrs do
    mock_maytapi_response(200, %{
      "success" => true,
      "data" => %{
        "chatId" => "78341114@c.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
      }
    })

    params = %{phone: "9829627508", message: "hi"}
    result = Message.send_text(attrs.organization_id, params)

    assert {:ok, %Tesla.Env{status: 200, body: response_body}} = result

    assert response_body == %{
             "success" => true,
             "data" => %{
               "chatId" => "78341114@c.us",
               "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
             }
           }
  end

  test "receive_text/1 receive text message correctly" do
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
      bsp_message_id: "2",
      caption: "A photo",
      url: "http://example.com/photo.jpg",
      content_type: "image",
      source_url: "http://example.com/photo.jpg",
      sender: %{phone: "1234567890", name: "Jane Doe"}
    }

    assert Message.receive_media(params) == expected_result
  end

  test "send_text/2 test possible error", attrs do
    mock_maytapi_response(200, %{
      "success" => false,
      "message" => "Product id is wrong! Please check your Account information."
    })

    params = %{phone: "9829627508", message: "hi"}
    result = Message.send_text(attrs.organization_id, params)

    assert {:ok, %Tesla.Env{status: 200, body: response_body}} = result

    assert response_body == %{
             "success" => false,
             "message" => "Product id is wrong! Please check your Account information."
           }
  end
end
