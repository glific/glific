defmodule Glific.Flows.ContactActionTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.Action,
    Flows.ContactAction,
    Flows.FlowContext,
    Flows.Templating,
    Messages.Message,
    Seeds.SeedsDev,
    Templates
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_providers()
    SeedsDev.seed_contacts()
    SeedsDev.seed_session_templates()
    SeedsDev.hsm_templates(organization)
    SeedsDev.seed_interactives(organization)
    :ok
  end

  test "optout", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    context =
      %FlowContext{contact_id: contact.id}
      |> Repo.preload(:contact)

    ContactAction.optout(context)

    contact = Contacts.get_contact!(contact.id)
    assert contact.optout_time != nil
    assert contact.optin_time == nil
  end

  test "send message text", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    # preload contact
    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:contact, :flow])

    action = %Action{text: "This is test message"}

    ContactAction.send_message(context, action, [])

    message =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "This is test message"
    assert message.flow_id == context.flow_id
  end

  test "send message template", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    context =
      Repo.insert!(%FlowContext{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: contact.organization_id
      })
      |> Repo.preload([:contact, :flow])

    [template | _] =
      Templates.list_session_templates(%{
        filter: Map.merge(attrs, %{shortcode: "otp", is_hsm: true})
      })

    templating = %Templating{
      template: template,
      variables: ["var_1", "var_2", "var_3"]
    }

    action = %Action{templating: templating}

    ContactAction.send_message(context, action, [])

    message =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "var_1 के लिए आपका OTP var_2 है। यह var_3 के लिए मान्य है।"
    assert message.flow_id == context.flow_id
  end

  test "send interactive message", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    context =
      Repo.insert!(%FlowContext{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: contact.organization_id
      })
      |> Repo.preload([:contact, :flow])

    [interactive_template | _] =
      Templates.InteractiveTemplates.list_interactives(%{
        filter: Map.merge(attrs, %{label: "Quick Reply Text"})
      })

    action = %Action{interactive_template_id: interactive_template.id}

    ContactAction.send_interactive_message(context, action, [])

    message =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "Glific is a two way communication platform"
    assert message.flow_id == context.flow_id
  end

  test "send interactive message with language changed", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    l2 = Glific.Settings.get_language!(2)
    assert {:ok, %Contact{} = contact} = Contacts.update_contact(contact, %{language_id: l2.id})
    # preload contact
    context =
      Repo.insert!(%FlowContext{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: contact.organization_id
      })
      |> Repo.preload([:contact, :flow])

    [interactive_template | _] =
      Templates.InteractiveTemplates.list_interactives(%{
        filter: Map.merge(attrs, %{label: "Are you excited for *Glific*?"})
      })

    action = %Action{interactive_template_id: interactive_template.id}

    ContactAction.send_interactive_message(context, action, [])

    message =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "ग्लिफ़िक सभी नई सुविधाओं के साथ आता है"
    assert message.flow_id == context.flow_id
  end

  test "send message translated template", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    l2 = Glific.Settings.get_language!(2)
    assert {:ok, %Contact{} = contact} = Contacts.update_contact(contact, %{language_id: l2.id})
    # preload contact
    context =
      Repo.insert!(%FlowContext{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: contact.organization_id
      })
      |> Repo.preload([:contact, :flow])

    [template | _] =
      Templates.list_session_templates(%{
        filter: Map.merge(attrs, %{shortcode: "otp", is_hsm: true})
      })

    templating = %Templating{
      template: template,
      variables: ["var_1", "var_2", "var_3"]
    }

    action = %Action{templating: templating}

    ContactAction.send_message(context, action, [])

    message =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "var_1 के लिए आपका OTP var_2 है। यह var_3 के लिए मान्य है।"
    assert message.flow_id == context.flow_id
  end

  test "send message template with attachments", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    context =
      Repo.insert!(%FlowContext{
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: contact.organization_id
      })
      |> Repo.preload([:contact, :flow])

    [template | _] =
      Templates.list_session_templates(%{
        filter: Map.merge(attrs, %{shortcode: "account_update", is_hsm: true})
      })

    templating = %Templating{
      template: template,
      variables: ["var_1", "var_2", "var_3"]
    }

    url = "https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg"
    type = "image"

    attachments = %{
      type => url
    }

    Glific.Fixtures.mock_validate_media(type)

    action = %Action{templating: templating, attachments: attachments}

    ContactAction.send_message(context, action, [])

    message =
      Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()
      |> Repo.preload(:media)

    # message media should be created
    assert message.media_id != nil
    assert message.is_hsm == true
    assert message.media.url == attachments["image"]

    assert message.media.caption ==
             "Hi var_1,\n\nYour account image was updated on var_2 by var_3 with above"
  end
end
