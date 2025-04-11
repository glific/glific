defmodule GlificWeb.Schema.WaReactionTest do
  @moduledoc false

  alias Glific.{
    Contacts.Contact,
    Groups.ContactWAGroup,
    Fixtures,
    Seeds.SeedsDev,
    WAGroup.WAMessage
  }

  alias GlificWeb.Providers.Maytapi.Controllers.MessageEventController

  use GlificWeb.ConnCase
  import Ecto.Query
  alias Glific.Repo

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    :ok
  end

  test "receive reaction success", %{staff: user} do
    contact = Fixtures.contact_fixture(organization_id: user.organization_id)

    wa_phone =
      Fixtures.wa_managed_phone_fixture(%{
        organization_id: user.organization_id,
        contact_id: contact.id
      })

    wa_grp =
      Fixtures.wa_group_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_phone.id
      })

    wa_message =
      Fixtures.wa_message_fixture(%{
        organization_id: user.organization_id,
        wa_managed_phone_id: wa_phone.id,
        wa_group_id: wa_grp.id
      })

    reaction_response =
      %{
        "data" => [
          %{
            "chatId" => "120363257@g.us",
            "msgId" => wa_message.bsp_id,
            "reaction" => "👍",
            "reactionId" =>
              "false_120363257477740000@g.us_3EB0D6348BCB67E1055857_919719266288@c.us",
            "reactorId" => "#{contact.phone}@.us",
            "rxid" => wa_message.bsp_id,
            "time" => 1_732_784_398
          }
        ],
        "type" => "ack"
      }

    MessageEventController.update_statuses(reaction_response, user.organization_id)

    message =
      WAMessage
      |> where(
        [wa],
        wa.bsp_id == ^wa_message.bsp_id and wa.organization_id == ^user.organization_id
      )
      |> Repo.one()

    message = Repo.preload(message, :reactions)
    assert Enum.any?(message.reactions, fn wa_reaction -> wa_reaction.reaction == "👍" end)

    # If same user change their reaction it should update
    reaction_response =
      %{
        "data" => [
          %{
            "chatId" => "120363257@g.us",
            "msgId" => wa_message.bsp_id,
            "reaction" => "😮",
            "reactionId" =>
              "false_120363257477740000@g.us_3EB0D6348BCB67E1055857_919719266288@c.us",
            "reactorId" => "#{contact.phone}@.us",
            "rxid" => wa_message.bsp_id,
            "time" => 1_732_784_398
          }
        ],
        "type" => "ack"
      }

    MessageEventController.update_statuses(reaction_response, user.organization_id)

    message =
      WAMessage
      |> where(
        [wa],
        wa.bsp_id == ^wa_message.bsp_id and wa.organization_id == ^user.organization_id
      )
      |> Repo.one()

    message = Repo.preload(message, :reactions)
    assert Enum.any?(message.reactions, fn wa_reaction -> wa_reaction.reaction == "😮" end)
  end

  test "handling ignored payload", user do
    payload =
      %{
        "chatId" => "120363257477740000@g.us",
        "msgId" =>
          "false_120363257477740000@g.us_DA8E37F4819D2982F3FAD894DBB287F3_919783328334@c.us",
        "rxid" =>
          "false_120363257477740000@g.us_DA8E37F4819D2982F3FAD894DBB287F3_919783328334@c.us",
        "time" => 1_739_257_237
      }

    assert is_nil(MessageEventController.update_statuses(payload, user.organization_id))
  end

  test "handling ignored payload-2", user do
    payload =
      %{
        "data" => [
          %{
            "chatId" => "120363257477740000@g.us",
            "msgId" =>
              "false_120363257477740000@g.us_DA8E37F4819D2982F3FAD894DBB287F3_919783328334@c.us",
            "rxid" =>
              "false_120363257477740000@g.us_DA8E37F4819D2982F3FAD894DBB287F3_919783328334@c.us",
            "time" => 1_739_257_237
          }
        ],
        "type" => "ack"
      }

    assert :ok = MessageEventController.update_statuses(payload, user.organization_id)
  end

  test "creates a contact when reacting to a message with a non-existent contact", user do
    org_id = user.organization_id
    contact = Fixtures.contact_fixture(organization_id: org_id)

    wa_phone =
      Fixtures.wa_managed_phone_fixture(%{
        organization_id: org_id,
        contact_id: contact.id
      })

    wa_grp =
      Fixtures.wa_group_fixture(%{
        organization_id: org_id,
        wa_managed_phone_id: wa_phone.id
      })

    wa_message =
      Fixtures.wa_message_fixture(%{
        organization_id: org_id,
        wa_managed_phone_id: wa_phone.id,
        wa_group_id: wa_grp.id
      })

    payload =
      %{
        "data" => [
          %{
            "chatId" => "120363253669863953@g.us",
            "msgId" => wa_message.bsp_id,
            "reaction" => "❤️",
            "reactionId" =>
              "false_120363253669863953@g.us_3AA9EF934027259C98F1_919425010449@c.us",
            "reactorId" => "919425010449@c.us",
            "rxid" => wa_message.bsp_id,
            "time" => 1_739_257_237
          }
        ],
        "type" => "ack"
      }

    assert :ok = MessageEventController.update_statuses(payload, org_id)
    contact = Repo.get_by(Contact, %{phone: "919425010449"})
    contact_wa_group = Repo.get_by(ContactWAGroup, %{contact_id: contact.id})

    assert contact != nil
    assert contact_wa_group.wa_group_id == wa_grp.id
    assert contact_wa_group.contact_id == contact.id
  end
end
