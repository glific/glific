defmodule Glific.Contacts.ChannelsTest do
  use Glific.DataCase, async: true

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.ContactChannel,
    Contacts.ContactHistory,
    Fixtures,
    Repo
  }

  setup do
    %{contact: Fixtures.contact_fixture()}
  end

  defp opt_in_history(contact_id, channel) do
    Repo.all(
      from(ch in ContactHistory,
        where:
          ch.contact_id == ^contact_id and ch.event_type == "contact_opted_in" and
            ch.channel == ^channel
      )
    )
  end

  describe "record_channel_optin/3" do
    test "inserts the opt-in and logs one history event on that channel", %{contact: contact} do
      assert {:ok, %ContactChannel{} = row} =
               Contacts.record_channel_optin(contact, :web, method: "web_channel_otp")

      assert row.channel == :web
      assert row.contact_id == contact.id
      assert row.organization_id == contact.organization_id
      assert row.optin_method == "web_channel_otp"
      assert row.optin_time
      assert [%{event_meta: %{"method" => "web_channel_otp"}}] = opt_in_history(contact.id, :web)
    end

    test "is idempotent: keeps the first opt-in time and logs nothing more", %{contact: contact} do
      first_time = ~U[2026-01-01 10:00:00Z]

      {:ok, first} =
        Contacts.record_channel_optin(contact, :web, method: "a", optin_time: first_time)

      assert {:ok, second} = Contacts.record_channel_optin(contact, :web, method: "b")

      assert second.id == first.id
      assert second.optin_time == first_time
      assert second.optin_method == "a"

      assert Repo.aggregate(
               from(cc in ContactChannel, where: cc.contact_id == ^contact.id),
               :count
             ) == 1

      assert [_one] = opt_in_history(contact.id, :web)
    end

    test "re-opting after an opt-out clears the opt-out and logs it", %{contact: contact} do
      {:ok, row} = Contacts.record_channel_optin(contact, :web, method: "a")

      row
      |> Ecto.Changeset.change(optout_time: DateTime.utc_now(:second), optout_method: "user")
      |> Repo.update!()

      refute Contacts.channel_opted_in?(contact, :web)

      assert {:ok, reopted} = Contacts.record_channel_optin(contact, :web, method: "b")

      assert reopted.optout_time == nil
      assert reopted.optout_method == nil
      assert reopted.optin_time == row.optin_time
      assert Contacts.channel_opted_in?(contact, :web)
      assert [_first, _again] = opt_in_history(contact.id, :web)
    end

    test "channels are independent and never touch the WhatsApp opt-in columns", %{
      contact: contact
    } do
      {:ok, _} = Contacts.record_channel_optin(contact, :web, method: "a")

      assert {:error, :not_found} = Contacts.fetch_channel(contact, :whatsapp)
      refute Contacts.channel_opted_in?(contact, :whatsapp)
      assert opt_in_history(contact.id, :whatsapp) == []

      reloaded = Contacts.get_contact!(contact.id)
      assert reloaded.optin_time == contact.optin_time
      assert reloaded.optin_status == contact.optin_status
      assert reloaded.optin_method == contact.optin_method
    end
  end

  describe "fetch_channel/2 and channel_opted_in?/2" do
    test "report nothing for a contact with no state", %{contact: contact} do
      assert {:error, :not_found} = Contacts.fetch_channel(contact, :web)
      refute Contacts.channel_opted_in?(contact, :web)
    end

    test "do not see another organization's row", %{contact: contact} do
      {:ok, _} = Contacts.record_channel_optin(contact, :web, method: "a")
      other_org = %{contact | organization_id: contact.organization_id + 1000}

      assert {:error, :not_found} = Contacts.fetch_channel(other_org, :web)
    end
  end
end
