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

  alias(Glific.Repo)
  alias GlificWeb.Providers.Maytapi.Controllers.MessageEventController

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
    "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
    "type" => "ack"
  }

  @poll_response_ack %{
    "data" => [
      %{
        "chatId" => "918657048983@c.us",
        "msgId" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d",
        "options" => [
          %{"id" => 0, "name" => "Hola", "votes" => 0},
          %{"id" => 1, "name" => "hoop", "votes" => 0},
          %{"id" => 2, "name" => "hola hoop", "votes" => 1}
        ],
        "rxid" => "false_120363257477740000@g.us_3EB0B6B66EDCB1C27C60_918547689517@c.us",
        "text" => "hola or hoop?",
        "time" => 1_733_818_876
      }
    ],
    "phoneId" => 47_309,
    "phone_id" => 47_309,
    "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
    "type" => "ack"
  }

  @error_event %{
    "code" => "F04",
    "data" => %{
      "id" => "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d",
      "message" => "Is it a Yes or No?",
      "only_one" => "true",
      "options[]" => ["Yes 😀", "No 😑"],
      "phone_id" => "47309",
      "to_number" => "120363238104@g.us",
      "type" => "poll"
    },
    "message" => "Options are required.",
    "phoneId" => 47_309,
    "phone_id" => 47_309,
    "product_id" => "3fa22108-f464-41e5-81d9-d8a298854430",
    "type" => "error"
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
        {:ok, %Tesla.Env{status: status, body: Jason.encode!(body)}}
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
    {:ok, wa_message} =
      WAMessages.update_message(message, %{
        bsp_id: "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d",
        bsp_status: :enqueued,
        status: :sent,
        sent_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    assert wa_message.flow == :outbound

    assert %Plug.Conn{} = post(conn, "/maytapi", @delivered_ack)
  end

  test "send message/2 in a whatsapp group, update_statuses function test", %{
    staff: user,
    conn: _conn
  } do
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

    MessageEventController.update_statuses(@delivered_ack, user.organization_id)

    message =
      WAMessage
      |> where([wa], wa.bsp_id == "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d")
      |> Repo.one()

    assert message.bsp_status == :delivered

    MessageEventController.update_statuses(@poll_response_ack, user.organization_id)

    message =
      WAMessage
      |> where([wa], wa.bsp_id == "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d")
      |> Repo.one()

    assert message.poll_content == %{
             "options" => [
               %{"id" => 0, "name" => "Hola", "votes" => 0},
               %{"id" => 1, "name" => "hoop", "votes" => 0},
               %{"id" => 2, "name" => "hola hoop", "votes" => 1}
             ],
             "text" => "hola or hoop?"
           }
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

  test "send poll in a whatsapp group", %{staff: user, conn: _conn} do
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

    wa_poll = Fixtures.wa_poll_fixture(%{label: "poll_a"})

    result =
      auth_query_gql_by(:send_msg, user,
        variables: %{
          "input" => %{
            "message" => "Message body testing send",
            "wa_group_id" => wa_grp.id,
            "wa_managed_phone_id" => wa_phone.id,
            "poll_id" => wa_poll.id
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "sendMessageInWaGroup", "errors"])
    assert message == nil

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :wa_group, with_scheduled: true)

    %WAMessage{body: "Poll question?", poll_content: content} =
      WAMessage
      |> where([wa], wa.bsp_id == "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d")
      |> Repo.one()

    assert is_map(content)
  end

  test "send poll in a whatsapp group, invalid poll_id", %{staff: user, conn: _conn} do
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
            "wa_managed_phone_id" => wa_phone.id,
            "poll_id" => 0
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "sendMessageInWaGroup", "errors"])
    refute is_nil(message)
  end

  test "error after sending poll in a whatsapp group", %{staff: user, conn: conn} do
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

    wa_poll = Fixtures.wa_poll_fixture(%{label: "poll_a"})

    result =
      auth_query_gql_by(:send_msg, user,
        variables: %{
          "input" => %{
            "message" => "Message body testing send",
            "wa_group_id" => wa_grp.id,
            "wa_managed_phone_id" => wa_phone.id,
            "poll_id" => wa_poll.id
          }
        }
      )

    assert {:ok, query_data} = result
    message = get_in(query_data, [:data, "sendMessageInWaGroup", "errors"])
    assert message == nil

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} ==
             Oban.drain_queue(queue: :wa_group, with_scheduled: true)

    %WAMessage{body: "Poll question?", poll_content: content} =
      WAMessage
      |> where([wa], wa.bsp_id == "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d")
      |> Repo.one()

    assert is_map(content)

    assert %Plug.Conn{} = post(conn, "/maytapi", @error_event)

    assert %WAMessage{errors: _err, bsp_status: :error} =
             WAMessage
             |> where([wa], wa.poll_id == ^wa_poll.id)
             |> Repo.one()
  end
end
