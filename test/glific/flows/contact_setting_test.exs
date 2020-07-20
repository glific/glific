defmodule Glific.Flows.ContactSettingTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.ContactSetting,
    Flows.FlowContext,
    Settings
  }

  setup do
    default_provider = Glific.SeedsDev.seed_providers()
    Glific.SeedsDev.seed_organizations(default_provider)
    Glific.SeedsDev.seed_contacts()
    :ok
  end

  test "set contact language" do
    language_label = "English (United States)"
    [language | _] = Settings.list_languages(%{label: language_label})

    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    ContactSetting.set_contact_language(flow_context, language_label)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.language_id == language.id

    # ensure that sending incorrect language label, raises an error
    language_label = "Incorrect label"

    assert_raise MatchError, fn ->
      ContactSetting.set_contact_language(flow_context, language_label)
    end
  end

  test "set contact name" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    updated_name = "Default updated name"
    ContactSetting.set_contact_name(flow_context, updated_name)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.name == updated_name
  end

  test "add contact preference" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    value = true
    updated_flow_context = ContactSetting.add_contact_preference(flow_context, preference, value)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.settings["preferences"] == %{preference => value}

    # default value of a preference should be set as true
    preference_2 = "test_preference_2"

    updated_flow_context =
      ContactSetting.add_contact_preference(updated_flow_context, preference_2)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.settings["preferences"][preference] == true

    # reset the contact preference when explicitly asked to do so
    preference = "reset"
    ContactSetting.add_contact_preference(updated_flow_context, preference)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.settings["preferences"] == %{}
  end

  test "delete contact preference" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    value = true
    updated_flow_context = ContactSetting.add_contact_preference(flow_context, preference, value)

    # set a preference to false
    ContactSetting.delete_contact_preference(updated_flow_context, preference)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.settings["preferences"][preference] == false
  end

  test "reset contact preference" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    value = true
    updated_flow_context = ContactSetting.add_contact_preference(flow_context, preference, value)

    # reset contact prefrence should remove all preferences
    ContactSetting.reset_contact_preference(updated_flow_context)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.settings["preferences"] == %{}
  end

  test "set contact preference" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    preference = Glific.string_clean(preference)
    updated_flow_context = ContactSetting.set_contact_preference(flow_context, preference)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.settings["preferences"] == %{preference => true}

    # reset the contact preference when preference is empty
    # To fix: understand requirement and check if nil should also work here
    preference = ""
    ContactSetting.set_contact_preference(updated_flow_context, preference)

    {:ok, updated_contact} = Repo.fetch_by(Contact, %{id: contact.id})
    assert updated_contact.settings["preferences"] == %{}
  end

  test "get contact preference" do
    [contact | _] = Contacts.list_contacts(%{filter: %{name: "Default receiver"}})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    # if settings is empty it should return empty list
    preferences = ContactSetting.get_contact_preferences(flow_context)

    assert preferences == []

    # get preference list
    preference = "test_preference"
    value = true
    updated_flow_context = ContactSetting.add_contact_preference(flow_context, preference, value)

    updated_preferences = ContactSetting.get_contact_preferences(updated_flow_context)

    assert updated_preferences == [preference]

    # get list of preferences
    preference_2 = "test_preference_2"

    updated_flow_context =
      ContactSetting.add_contact_preference(updated_flow_context, preference_2)

    updated_preferences = ContactSetting.get_contact_preferences(updated_flow_context)

    assert preference in updated_preferences
    assert preference_2 in updated_preferences
  end
end
