defmodule GlificWeb.Providers.Maytapi.Controllers.MessageEventControllerTest do
  use GlificWeb.ConnCase
  use Oban.Testing, repo: Glific.Repo, prefix: "global"

  import Ecto.Query

  alias Glific.{
    Communications.GroupMessage,
    Contacts,
    Fixtures,
    Providers.Maytapi.Message,
    Repo,
    WAGroup.PendingReactionWorker,
    WAGroup.WAMessage,
    WAGroup.WaReaction
  }

  alias GlificWeb.Providers.Maytapi.Controllers.{
    DefaultController,
    MessageEventController
  }

  @group_bsp_id "120363238104@g.us"
  @parent_api_id "a3ff8460-c710-11ee-a8e7-5fbaaf152c1d"
  @parent_key_id "3EB0C0FFEE0000000001"
  @parent_whatsapp_id "true_#{@group_bsp_id}_#{@parent_key_id}_917834811114@c.us"
  @reactor_phone "919812345678"
  @reaction_whatsapp_id "false_#{@group_bsp_id}_AC1B50CEE745CF9602ABBD26BD8062A2_#{@reactor_phone}@c.us"

  setup %{organization_id: organization_id} do
    wa_managed_phone = Fixtures.get_wa_managed_phone(organization_id)

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: wa_managed_phone.id,
        bsp_id: @group_bsp_id
      })

    parent_message =
      Fixtures.wa_message_fixture(%{
        organization_id: organization_id,
        wa_group_id: wa_group.id,
        flow: :outbound,
        bsp_id: @parent_api_id
      })

    %{parent_message: parent_message, wa_group: wa_group}
  end

  defp message_format_reaction(parent_whatsapp_id, reaction \\ "🙏") do
    %{
      "type" => "message",
      "conversation" => @group_bsp_id,
      "conversation_name" => "Test group",
      "receiver" => "917834811114",
      "phone_id" => 242,
      "message" => %{
        "_serialized" => @reaction_whatsapp_id,
        "id" => @reaction_whatsapp_id,
        "fromMe" => false,
        "parentMsgId" => parent_whatsapp_id,
        "reaction" => reaction,
        "type" => "reaction"
      },
      "user" => %{
        "id" => "#{@reactor_phone}@c.us",
        "name" => "Reactor",
        "phone" => @reactor_phone
      }
    }
  end

  defp delivered_ack(rxid) do
    %{
      "type" => "ack",
      "data" => [
        %{
          "ackType" => "delivered",
          "msgId" => @parent_api_id,
          "rxid" => rxid,
          "chatId" => @group_bsp_id
        }
      ]
    }
  end

  defp ack_format_reaction(reaction) do
    %{
      "type" => "ack",
      "data" => [
        %{
          "chatId" => @group_bsp_id,
          "msgId" => @parent_api_id,
          "reaction" => reaction,
          "reactionId" => @reaction_whatsapp_id,
          "reactorId" => "#{@reactor_phone}@c.us",
          "rxid" => @parent_whatsapp_id
        }
      ]
    }
  end

  defp reactions_for(wa_message_id) do
    WaReaction
    |> where([wa_reaction], wa_reaction.wa_message_id == ^wa_message_id)
    |> Repo.all()
  end

  defp wait_for_reactions(wa_message_id, expected_count),
    do: wait_for(wa_message_id, &(length(&1) == expected_count))

  defp wait_for(wa_message_id, done?, attempts \\ 50)

  defp wait_for(wa_message_id, _done?, 0), do: reactions_for(wa_message_id)

  defp wait_for(wa_message_id, done?, attempts) do
    reactions = reactions_for(wa_message_id)

    if done?.(reactions) do
      reactions
    else
      Process.sleep(50)
      wait_for(wa_message_id, done?, attempts - 1)
    end
  end

  describe "delivery ack" do
    test "stores the WhatsApp key id from rxid on the sent message",
         %{organization_id: organization_id, parent_message: parent_message} do
      assert is_nil(parent_message.whatsapp_key_id)

      MessageEventController.update_statuses(
        delivered_ack(@parent_whatsapp_id),
        organization_id
      )

      updated_message = Repo.get!(WAMessage, parent_message.id)
      assert updated_message.whatsapp_key_id == @parent_key_id
      assert updated_message.bsp_status == :delivered
    end

    test "leaves the key id untouched when the ack has no rxid",
         %{organization_id: organization_id, parent_message: parent_message} do
      MessageEventController.update_statuses(delivered_ack(nil), organization_id)

      updated_message = Repo.get!(WAMessage, parent_message.id)
      assert is_nil(updated_message.whatsapp_key_id)
      assert updated_message.bsp_status == :delivered
    end
  end

  describe "message-format reaction" do
    setup %{organization_id: organization_id} do
      MessageEventController.update_statuses(
        delivered_ack(@parent_whatsapp_id),
        organization_id
      )

      :ok
    end

    test "is routed to the reaction handler and saved on the sent message",
         %{conn: conn, parent_message: parent_message} do
      conn = post(conn, "/maytapi", message_format_reaction(@parent_whatsapp_id))

      assert conn.private.phoenix_controller == MessageEventController
      assert conn.private.phoenix_action == :reaction
      assert json_response(conn, 200) == nil

      assert [%WaReaction{reaction: "🙏", bsp_id: @reaction_whatsapp_id}] =
               wait_for_reactions(parent_message.id, 1)
    end

    test "matches the parent message when its participant arrives as @lid",
         %{conn: conn, parent_message: parent_message} do
      lid_parent_id = "true_#{@group_bsp_id}_#{@parent_key_id}_143851234567890@lid"

      post(conn, "/maytapi", message_format_reaction(lid_parent_id))

      assert [%WaReaction{reaction: "🙏"}] = wait_for_reactions(parent_message.id, 1)
    end

    test "matches an inbound parent message by its WhatsApp bsp_id",
         %{conn: conn, organization_id: organization_id, wa_group: wa_group} do
      inbound_whatsapp_id = "false_#{@group_bsp_id}_3EB0INBOUND0000000001_919876500000@c.us"

      inbound_message =
        Fixtures.wa_message_fixture(%{
          organization_id: organization_id,
          wa_group_id: wa_group.id,
          bsp_id: inbound_whatsapp_id
        })

      post(conn, "/maytapi", message_format_reaction(inbound_whatsapp_id))

      assert [%WaReaction{reaction: "🙏"}] = wait_for_reactions(inbound_message.id, 1)
    end

    test "a changed reaction updates the existing row",
         %{conn: conn, parent_message: parent_message} do
      post(conn, "/maytapi", message_format_reaction(@parent_whatsapp_id, "👍"))
      assert [%WaReaction{reaction: "👍"}] = wait_for_reactions(parent_message.id, 1)

      post(conn, "/maytapi", message_format_reaction(@parent_whatsapp_id, "❤️"))

      assert [%WaReaction{reaction: "❤️"}] =
               wait_for(parent_message.id, &match?([%WaReaction{reaction: "❤️"}], &1))
    end

    test "a removed reaction deletes the existing row",
         %{conn: conn, organization_id: organization_id, parent_message: parent_message} do
      post(conn, "/maytapi", message_format_reaction(@parent_whatsapp_id, "👍"))
      assert [%WaReaction{reaction: "👍"}] = wait_for_reactions(parent_message.id, 1)

      assert {:ok, :removed} =
               @parent_whatsapp_id
               |> message_format_reaction("")
               |> Message.receive_reaction()
               |> GroupMessage.receive_reaction_msg(organization_id)

      assert [] == reactions_for(parent_message.id)
    end

    test "removing a reaction that was never stored creates nothing and is not retried",
         %{organization_id: organization_id, parent_message: parent_message} do
      assert {:ok, :removed} =
               @parent_whatsapp_id
               |> message_format_reaction("")
               |> Message.receive_reaction()
               |> GroupMessage.receive_reaction_msg(organization_id)

      assert [] == reactions_for(parent_message.id)
      assert {:error, :not_found} = Contacts.fetch_by_identity(:whatsapp, @reactor_phone)
      refute_enqueued(worker: PendingReactionWorker)
    end

    test "the same reaction in both formats is stored once",
         %{conn: conn, organization_id: organization_id, parent_message: parent_message} do
      post(conn, "/maytapi", message_format_reaction(@parent_whatsapp_id, "👍"))
      assert [_reaction] = wait_for_reactions(parent_message.id, 1)

      MessageEventController.update_statuses(ack_format_reaction("👍"), organization_id)

      assert [%WaReaction{reaction: "👍"}] = reactions_for(parent_message.id)
    end

    test "a reaction to an unknown message is not saved and is scheduled for a retry",
         %{organization_id: organization_id, parent_message: parent_message} do
      unknown_parent_id = "true_#{@group_bsp_id}_3EB0UNKNOWN0000000000_917834811114@c.us"

      assert {:error, :not_found} =
               @parent_whatsapp_id
               |> message_format_reaction()
               |> put_in(["message", "parentMsgId"], unknown_parent_id)
               |> Message.receive_reaction()
               |> GroupMessage.receive_reaction_msg(organization_id)

      assert [] == reactions_for(parent_message.id)

      assert_enqueued(
        worker: PendingReactionWorker,
        args: %{organization_id: organization_id, retry: 0}
      )
    end

    test "a reaction from an unresolved @lid participant is skipped",
         %{organization_id: organization_id, parent_message: parent_message} do
      lid_reaction =
        @parent_whatsapp_id
        |> message_format_reaction()
        |> put_in(["user"], %{"id" => "143851234567890@lid", "phone" => ""})
        |> put_in(["message", "id"], "false_#{@group_bsp_id}_AC1B50_143851234567890@lid")
        |> put_in(["message", "_serialized"], "false_#{@group_bsp_id}_AC1B50_143851234567890@lid")

      assert {:error, :unresolved_reactor} =
               lid_reaction
               |> Message.receive_reaction()
               |> GroupMessage.receive_reaction_msg(organization_id)

      assert [] == reactions_for(parent_message.id)
      refute_enqueued(worker: PendingReactionWorker)
    end

    test "a reaction from the managed phone itself creates no contact, membership or reaction",
         %{conn: conn, parent_message: parent_message} do
      managed_phone = "919000000099"

      own_reaction =
        @parent_whatsapp_id
        |> message_format_reaction()
        |> Map.put("receiver", managed_phone)
        |> put_in(["message", "fromMe"], true)
        |> put_in(["user"], %{"id" => "#{managed_phone}@c.us", "phone" => managed_phone})

      conn = post(conn, "/maytapi", own_reaction)

      assert conn.private.phoenix_action == :reaction
      assert json_response(conn, 200) == nil
      assert [] == reactions_for(parent_message.id)
      assert {:error, :not_found} = Contacts.fetch_by_identity(:whatsapp, managed_phone)
      refute_enqueued(worker: PendingReactionWorker)
    end
  end

  describe "ack-format reaction" do
    test "an empty reaction removes the row saved in the ack format",
         %{organization_id: organization_id, parent_message: parent_message} do
      MessageEventController.update_statuses(ack_format_reaction("👍"), organization_id)
      assert [%WaReaction{reaction: "👍"}] = reactions_for(parent_message.id)

      MessageEventController.update_statuses(ack_format_reaction(""), organization_id)
      assert [] == reactions_for(parent_message.id)
    end

    test "is still saved against the sent message",
         %{organization_id: organization_id, parent_message: parent_message} do
      MessageEventController.update_statuses(ack_format_reaction("😮"), organization_id)

      assert [%WaReaction{reaction: "😮"}] = reactions_for(parent_message.id)
    end
  end

  describe "unhandled message events" do
    test "are acknowledged by the default controller", %{conn: conn} do
      poll_vote =
        @parent_whatsapp_id
        |> message_format_reaction()
        |> put_in(["message", "type"], "pollVoteUpdate")

      conn = post(conn, "/maytapi", poll_vote)

      assert conn.private.phoenix_controller == DefaultController
      assert conn.params["unknown"] == ["message", "pollVoteUpdate"]
      assert json_response(conn, 200) == nil
    end
  end
end
