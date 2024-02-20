defmodule GlificWeb.Schema.Api.WaMessageTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Partners,
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

  load_gql(:send_msg, GlificWeb.Schema, "assets/gql/messages/wa_group_message.gql")

  test "send message/2 in a whatsapp group", %{staff: user} do
    mock_maytapi_response(200, %{
      "success" => true,
      "data" => %{
        "chatId" => "120363238104@g.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
      }
    })

    message =
      WAManagedPhonesFixtures.wa_managed_phone_fixture(%{
        organization_id: user.organization_id
      })

    result =
      auth_query_gql_by(:send_msg, user,
        variables: %{
          "input" => %{
            "message" => "Message body",
            "bsp_id" => "120363238104@g.us",
            "phone" => message.phone
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "sendMessageInWaGroup", "error"])
    assert message == nil
  end
end
