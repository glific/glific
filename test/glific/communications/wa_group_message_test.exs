defmodule Glific.Communications.GroupMessageTest do
  # DataCase rather than a ConnCase/GraphQL boundary: these two cases exercise the
  # WAMessage lookup branches inside `receive_reaction_msg/2` directly (AppSignal
  # incidents #17 and #7). The webhook controller layer already has a happy-path
  # test (test/glific_web/schema/wa_reaction_test.exs); these are regression tests
  # for the failure branches that a generic controller-level test wouldn't isolate.
  use Glific.DataCase

  alias Faker.Phone

  alias Glific.{
    Communications.GroupMessage,
    Contacts.Contact,
    Fixtures,
    Repo,
    WAGroup.WAMessage,
    WAGroup.WaReaction
  }

  describe "receive_reaction_msg/2 — no matching WAMessage (incident #17)" do
    test "does not raise and skips the reaction when no WAMessage matches the bsp_id", %{
      organization_id: organization_id
    } do
      phone = Phone.EnUs.phone()
      missing_bsp_id = "no-such-bsp-id-#{System.unique_integer([:positive])}"

      params = %{
        "reactorId" => "#{phone}@c.us",
        "reaction" => "👍",
        "msgId" => missing_bsp_id,
        "reactionId" => "reaction-bsp-id-#{System.unique_integer([:positive])}"
      }

      refute Repo.get_by(WAMessage, %{bsp_id: missing_bsp_id, organization_id: organization_id})

      assert {:error, error} = GroupMessage.receive_reaction_msg(params, organization_id)
      assert error =~ "no WAMessage found"

      refute Repo.get_by(Contact, %{phone: phone})
      refute Repo.get_by(WaReaction, %{bsp_id: params["reactionId"]})
    end
  end

  describe "receive_reaction_msg/2 — WAMessage found but wa_group_id is nil (incident #7)" do
    test "does not raise and skips the reaction instead of calling ContactWAGroups", attrs do
      wa_managed_phone = Fixtures.wa_managed_phone_fixture(attrs)

      wa_message =
        Fixtures.wa_message_fixture(%{
          organization_id: attrs.organization_id,
          wa_managed_phone_id: wa_managed_phone.id
        })

      assert is_nil(wa_message.wa_group_id)

      phone = Phone.EnUs.phone()

      params = %{
        "reactorId" => "#{phone}@c.us",
        "reaction" => "❤️",
        "msgId" => wa_message.bsp_id,
        "reactionId" => "reaction-bsp-id-#{System.unique_integer([:positive])}"
      }

      assert {:error, error} = GroupMessage.receive_reaction_msg(params, attrs.organization_id)
      assert error =~ "nil wa_group_id"

      # If ContactWAGroups.create_contact_wa_group/1 had been reached, it would have
      # required a contact created by Contacts.maybe_create_contact/1 first — so the
      # absence of that contact proves the happy-path branch was never entered.
      refute Repo.get_by(Contact, %{phone: phone})
      refute Repo.get_by(WaReaction, %{wa_message_id: wa_message.id})
    end
  end
end
