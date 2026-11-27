defmodule Glific.Communications.GroupMessageTest do
  use Glific.DataCase

  alias Glific.{
    Communications.GroupMessage,
    Fixtures,
    WAGroup.WAMessage
  }

  doctest WAMessage, import: true

  @key_id "3EB0A1B2C3D4E5F60718"

  setup %{organization_id: organization_id} do
    wa_managed_phone = Fixtures.get_wa_managed_phone(organization_id)

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: wa_managed_phone.id
      })

    %{wa_group: wa_group}
  end

  describe "whatsapp key id on insert" do
    test "is derived from a WhatsApp bsp_id", %{organization_id: organization_id} do
      wa_message =
        Fixtures.wa_message_fixture(%{
          organization_id: organization_id,
          bsp_id: "false_120363238104@g.us_#{@key_id}_919876500000@c.us"
        })

      assert wa_message.whatsapp_key_id == @key_id
    end

    test "is nil for an API uuid bsp_id", %{organization_id: organization_id} do
      wa_message =
        Fixtures.wa_message_fixture(%{
          organization_id: organization_id,
          flow: :outbound,
          bsp_id: Ecto.UUID.generate()
        })

      assert is_nil(wa_message.whatsapp_key_id)
    end
  end

  describe "fetch_by_whatsapp_id/2" do
    test "finds a message by key id whatever the participant form",
         %{organization_id: organization_id, wa_group: wa_group} do
      wa_message =
        Fixtures.wa_message_fixture(%{
          organization_id: organization_id,
          wa_group_id: wa_group.id,
          bsp_id: "false_120363238104@g.us_#{@key_id}_919876500000@c.us"
        })

      assert {:ok, %WAMessage{id: id}} =
               GroupMessage.fetch_by_whatsapp_id(
                 "false_120363238104@g.us_#{@key_id}_143851234567890@lid",
                 organization_id
               )

      assert id == wa_message.id
    end

    test "falls back to an exact bsp_id match for non-WhatsApp ids",
         %{organization_id: organization_id} do
      api_id = Ecto.UUID.generate()

      wa_message =
        Fixtures.wa_message_fixture(%{
          organization_id: organization_id,
          flow: :outbound,
          bsp_id: api_id
        })

      assert {:ok, %WAMessage{id: id}} =
               GroupMessage.fetch_by_whatsapp_id(api_id, organization_id)

      assert id == wa_message.id
    end

    test "does not match another organization's message",
         %{organization_id: organization_id} do
      Fixtures.wa_message_fixture(%{
        organization_id: organization_id,
        bsp_id: "false_120363238104@g.us_#{@key_id}_919876500000@c.us"
      })

      assert {:error, :not_found} =
               GroupMessage.fetch_by_whatsapp_id(
                 "false_120363238104@g.us_#{@key_id}_919876500000@c.us",
                 organization_id + 1_000_000
               )
    end

    test "returns not found for an unknown id", %{organization_id: organization_id} do
      assert {:error, :not_found} =
               GroupMessage.fetch_by_whatsapp_id(
                 "true_120363238104@g.us_3EB0MISSING_919876500000@c.us",
                 organization_id
               )
    end

    test "returns missing parent id when there is no id to look up",
         %{organization_id: organization_id} do
      assert {:error, :missing_parent_id} =
               GroupMessage.fetch_by_whatsapp_id(nil, organization_id)

      assert {:error, :missing_parent_id} = GroupMessage.fetch_by_whatsapp_id("", organization_id)
    end
  end
end
