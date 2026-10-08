defmodule Glific.Contacts.ContactWithoutPhoneTest do
  use Glific.DataCase

  alias Glific.{
    Communications.WebMessage,
    Contacts,
    Contacts.Contact,
    Fixtures,
    Flows,
    Flows.Broadcast,
    Flows.FlowContext,
    Flows.MessageBroadcast,
    Flows.MessageBroadcastContact,
    Groups,
    Messages,
    Messages.Message,
    Repo
  }

  setup %{organization_id: organization_id} do
    %{contact: Fixtures.contact_without_phone_fixture(%{organization_id: organization_id})}
  end

  defp active_flow(organization_id) do
    [flow | _] = Flows.list_flows(%{filter: %{organization_id: organization_id}})
    {:ok, flow} = Flows.update_flow(flow, %{is_active: true})
    flow
  end

  describe "inbound" do
    test "a web message is stored against the contact", %{contact: contact} do
      assert {:ok, %Message{} = message} =
               WebMessage.receive_message(contact, %{body: "hello"}, :text)

      assert %{contact_id: contact_id, sender_id: sender_id, channel: :web} = message
      assert contact_id == contact.id
      assert sender_id == contact.id
    end

    test "a WhatsApp inbound with no phone never resolves to the contact",
         %{contact: contact, organization_id: organization_id} do
      assert {:error, %Ecto.Changeset{}} =
               Contacts.maybe_create_contact(%{phone: nil, organization_id: organization_id})

      assert [] ==
               Message
               |> where([m], m.contact_id == ^contact.id)
               |> Repo.all()
    end
  end

  describe "outbound" do
    test "a WhatsApp send is refused before reaching the provider", %{contact: contact} do
      assert {:error, "Contact has no WhatsApp number."} ==
               Messages.create_and_send_message(%{
                 body: "hi",
                 flow: :outbound,
                 type: :text,
                 sender_id: Glific.Partners.organization_contact_id(contact.organization_id),
                 receiver_id: contact.id,
                 organization_id: contact.organization_id
               })
    end

    test "a web send is delivered", %{contact: contact} do
      assert {:ok, %Message{} = message} =
               Messages.create_and_send_message(%{
                 body: "hi on the web",
                 flow: :outbound,
                 type: :text,
                 channel: :web,
                 sender_id: Glific.Partners.organization_contact_id(contact.organization_id),
                 receiver_id: contact.id,
                 organization_id: contact.organization_id
               })

      assert %{status: status} = Repo.reload!(message)
      refute status == :error
    end
  end

  describe "flows" do
    test "a flow started on the web channel runs and replies on the web",
         %{contact: contact, organization_id: organization_id} do
      flow = active_flow(organization_id)

      {:ok, _flow} = Flows.start_contact_flow(flow, contact, %{}, :web)

      assert {:ok, %FlowContext{channel: :web}} =
               Repo.fetch_by(FlowContext, %{flow_id: flow.id, contact_id: contact.id})

      replies =
        Message
        |> where([m], m.contact_id == ^contact.id and m.flow == :outbound)
        |> Repo.all()

      assert replies != []
      assert Enum.all?(replies, &(&1.channel == :web and &1.status != :error))
    end

    test "a flow started on WhatsApp stops without sending or touching other contacts",
         %{contact: contact, organization_id: organization_id} do
      flow = active_flow(organization_id)
      opted_out_before = Repo.aggregate(where(Contact, [c], not is_nil(c.optout_time)), :count)

      Flows.start_contact_flow(flow, contact)

      assert {:ok, %FlowContext{}} =
               Repo.fetch_by(FlowContext, %{flow_id: flow.id, contact_id: contact.id})

      assert [] ==
               Message
               |> where([m], m.contact_id == ^contact.id and m.flow == :outbound)
               |> where([m], m.status != :error)
               |> Repo.all()

      assert opted_out_before ==
               Repo.aggregate(where(Contact, [c], not is_nil(c.optout_time)), :count)
    end
  end

  describe "broadcast" do
    test "a WhatsApp collection flow completes, and sends nothing to the contact without a phone",
         %{contact: contact, organization_id: organization_id} do
      flow = active_flow(organization_id)
      with_phone = Fixtures.contact_fixture(%{organization_id: organization_id})
      group = Fixtures.group_fixture(%{organization_id: organization_id})

      for member <- [contact, with_phone] do
        Groups.create_contact_group(%{
          group_id: group.id,
          contact_id: member.id,
          organization_id: organization_id
        })
      end

      {:ok, _flow} = Flows.start_group_flow(flow, [group.id], %{})
      Broadcast.execute_broadcasts(organization_id)
      Broadcast.execute_broadcasts(organization_id)

      {:ok, broadcast} = Repo.fetch_by(MessageBroadcast, %{group_id: group.id, flow_id: flow.id})

      statuses =
        MessageBroadcastContact
        |> where([mbc], mbc.message_broadcast_id == ^broadcast.id)
        |> select([mbc], {mbc.contact_id, mbc.status})
        |> Repo.all()
        |> Map.new()

      assert statuses[with_phone.id] == "processed"
      assert statuses[contact.id] == "processed"
      assert broadcast.completed_at != nil

      assert [] ==
               Message
               |> where([m], m.contact_id == ^contact.id and m.flow == :outbound)
               |> where([m], m.status != :error)
               |> Repo.all()
    end
  end

  describe "the person" do
    test "can be updated, blocked and deleted", %{contact: contact} do
      assert {:ok, %Contact{name: "Ravi"}} = Contacts.update_contact(contact, %{name: "Ravi"})

      assert {:ok, %Contact{status: :blocked}} =
               Contacts.update_contact(contact, %{status: :blocked})

      assert {:ok, _} = Contacts.delete_contact(Repo.reload!(contact))
    end

    test "is listed and found by name, with no phone or masked phone", %{contact: contact} do
      assert [%Contact{phone: nil} = found] =
               Contacts.list_contacts(%{filter: %{name: contact.name}})

      assert found.id == contact.id
      assert %Contact{masked_phone: nil} = Contact.populate_masked_phone(found)
    end
  end
end
