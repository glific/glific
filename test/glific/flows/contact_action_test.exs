defmodule Glific.Flows.ContactActionTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Flows.Action,
    Flows.ContactAction,
    Flows.FlowContext
  }

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_contacts()
    :ok
  end

  test "optout" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    ContactAction.optout(context)

    contact = Contacts.get_contact!(contact.id)
    assert contact.optout_time != nil
    assert contact.optin_time == nil
  end

  test "send message text" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    ContactAction.send_message(context, %Action{text: "This is test message"})

    message =
      Glific.Messages.Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "This is test message"
  end
end
