defmodule GlificWeb.Schema.Api.WaMessageTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  import Ecto.Query

  alias Glific.{
    Fixtures,
    Messages.MessageMedia,
    Partners,
    Providers.Maytapi,
    Providers.Maytapi.WAMessages,
    Seeds.SeedsDev,
    WAGroup.WAMessage,
    WAMessages
  }

  alias Glific.Repo

  @delivered_ack %{
    "data" => [
      %{
        "ackCode" => 1,
        "ackType" => "delivered",
        "chatId" => "120363238104@g.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d",
        "rxid" => "true_120363213833166449@g.us_3EB00732AE084A0E224F4D_918547689517@c.us",
        "time" => 1_710_342_107
      }
    ],
    "phoneId" => 47_309,
    "phone_id" => 47_309,
    "product_id" => "5bb39ba2-d0f4-4fb5-8bd3-a1f26c50559c",
    "type" => "ack"
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

  test "send message/2 in a whatsapp group", %{staff: user, conn: conn} do
    mock_maytapi_response(200, %{
      "success" => true,
      "data" => %{
        "chatId" => "120363238104@g.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
      }
    })

    wa_phone =
      Fixtures.wa_managed_phone_fixture(%{
        organization_id: user.organization_id
      })

    wa_grp =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_phone.id
      })

    result =
      auth_query_gql_by(:send_msg, user,
        variables: %{
          "input" => %{
            "message" => "Message body testing send",
            "wa_group_id" => wa_grp.id,
            "wa_managed_phone_id" => wa_phone.id
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "sendMessageInWaGroup", "error"])
    assert message == nil

    message =
      WAMessage
      |> where([wa], wa.body == "Message body testing send")
      |> Repo.one()

    # manually updating wa_message as we do in real
    WAMessages.update_message(message, %{
      bsp_id: "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d",
      bsp_status: :enqueued,
      status: :sent,
      flow: :outbound,
      sent_at: DateTime.truncate(DateTime.utc_now(), :second)
    })

    _conn = post(conn, "/maytapi", @delivered_ack)

    message =
      WAMessage
      |> where([wa], wa.bsp_id == "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d")
      |> Repo.one()

    assert message.bsp_status == :delivered
  end

  test "send media message with caption", %{staff: user, conn: _conn} do
    wa_phone =
      Fixtures.wa_managed_phone_fixture(%{
        organization_id: user.organization_id
      })

    wa_grp =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_phone.id
      })

    message_media = Fixtures.message_media_fixture(%{organization_id: user.organization_id})

    wa_message =
      Fixtures.wa_message_fixture(%{
        organization_id: user.organization_id,
        media_id: message_media.id
      })

    assert {:ok, %{args: %{"payload" => %{"text" => _}}}} =
             Repo.preload(wa_message, [:media])
             |> Maytapi.WAMessages.send_image(%{
               wa_group_bsp_id: wa_grp.bsp_id,
               phone_id: wa_phone.phone_id,
               phone: wa_phone.phone
             })
  end

  test "send media message without caption", %{staff: user, conn: _conn} do
    wa_phone =
      Fixtures.wa_managed_phone_fixture(%{
        organization_id: user.organization_id
      })

    wa_grp =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_phone.id
      })

    message_media = Fixtures.message_media_fixture(%{organization_id: user.organization_id})

    MessageMedia.changeset(message_media, %{caption: ""})
    |> Repo.update!()

    wa_message =
      Fixtures.wa_message_fixture(%{
        organization_id: user.organization_id,
        media_id: message_media.id
      })

    assert {:ok, %{args: %{"payload" => %{"message" => _}}}} =
             Repo.preload(wa_message, [:media])
             |> Maytapi.WAMessages.send_image(%{
               wa_group_bsp_id: wa_grp.bsp_id,
               phone_id: wa_phone.phone_id,
               phone: wa_phone.phone
             })
  end
end
