defmodule Glific.Flows.ContactActionTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Flows.Action,
    Flows.ContactAction,
    Flows.FlowContext,
    Flows.Templating
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

    action = %Action{text: "This is test message"}

    ContactAction.send_message(context, action)

    message =
      Glific.Messages.Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "This is test message"
  end

  test "send message template" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    [template | _] =
      Glific.Templates.list_session_templates(%{
        filter: %{shortcode: "hsm", label: "HSM3", is_hsm: true}
      })

    templating = %Templating{
      template: template,
      variables: ["var_1", "var_2", "var_3"]
    }

    action = %Action{templating: templating}

    ContactAction.send_message(context, action)

    message =
      Glific.Messages.Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "Your var_1 number var_2 has been var_3."
  end
end
