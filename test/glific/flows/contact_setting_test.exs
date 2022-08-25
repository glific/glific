defmodule Glific.Flows.ContactSettingTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Contacts,
    Fixtures,
    Flows.ContactSetting,
    Flows.FlowContext,
    Profiles,
    Seeds.SeedsDev,
    Settings.Language
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    :ok
  end

  test "set contact language", attrs do
    language_label = "English"

    {:ok, language} = Repo.fetch_by(Language, %{label: language_label})

    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    flow_context =
      %FlowContext{contact_id: contact.id, flow_id: 1} |> Repo.preload([:contact, :flow])

    ContactSetting.set_contact_language(flow_context, language_label)

    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.language_id == language.id

    # ensure that sending incorrect language label, raises an error
    language_label = "Incorrect label"

    assert_raise RuntimeError, fn ->
      ContactSetting.set_contact_language(flow_context, language_label)
    end
  end

  test "set contact language for contact with active profile changes profile language and contact language" do
    profile = Fixtures.profile_fixture()
    language_label = "Hindi"

    {:ok, language} = Repo.fetch_by(Language, %{label: language_label})
    {:ok, contact} = Repo.fetch_by(Contacts.Contact, %{id: profile.contact_id})

    # preload contact
    flow_context =
      %FlowContext{contact_id: contact.id, flow_id: 1} |> Repo.preload([:contact, :flow])

    ContactSetting.set_contact_language(flow_context, language_label)

    updated_contact = Contacts.get_contact!(contact.id)
    {:ok, active_profile} = Repo.fetch_by(Profiles.Profile, %{id: profile.id})

    assert updated_contact.language_id == language.id
    assert active_profile.language_id == language.id
  end

  test "set contact name", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    flow_context =
      %FlowContext{contact_id: contact.id, flow_id: 1} |> Repo.preload([:contact, :flow])

    updated_name = "Default updated name"
    ContactSetting.set_contact_name(flow_context, updated_name)

    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.name == updated_name
  end

  test "add contact preference", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    value = true
    updated_flow_context = ContactSetting.add_contact_preference(flow_context, preference, value)

    preference = Glific.string_clean(preference)
    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.settings["preferences"] == %{preference => value}

    # default value of a preference should be set as true
    preference_2 = "test_preference_2"

    updated_flow_context =
      ContactSetting.add_contact_preference(updated_flow_context, preference_2)

    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.settings["preferences"][preference] == true

    # reset the contact preference when explicitly asked to do so
    preference = "reset"
    ContactSetting.add_contact_preference(updated_flow_context, preference)

    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.settings["preferences"] == %{}
  end

  test "delete contact preference", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    value = true
    updated_flow_context = ContactSetting.add_contact_preference(flow_context, preference, value)

    # set a preference to false
    ContactSetting.delete_contact_preference(updated_flow_context, preference)

    preference = Glific.string_clean(preference)
    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.settings["preferences"][preference] == false
  end

  test "reset contact preference", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    value = true
    updated_flow_context = ContactSetting.add_contact_preference(flow_context, preference, value)

    # reset contact prefrence should remove all preferences
    ContactSetting.reset_contact_preference(updated_flow_context)

    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.settings["preferences"] == %{}
  end

  test "set contact preference", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    flow_context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    preference = "test_preference"
    updated_flow_context = ContactSetting.set_contact_preference(flow_context, preference)

    preference = Glific.string_clean(preference)
    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.settings["preferences"] == %{preference => true}

    # reset the contact preference when preference is empty
    # To fix: understand requirement and check if nil should also work here
    preference = ""
    ContactSetting.set_contact_preference(updated_flow_context, preference)

    updated_contact = Contacts.get_contact!(contact.id)
    assert updated_contact.settings["preferences"] == %{}
  end

  test "get contact preference", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

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

    preference = Glific.string_clean(preference)
    assert updated_preferences == [preference]

    # get list of preferences
    preference_2 = "test_preference_2"

    updated_flow_context =
      ContactSetting.add_contact_preference(updated_flow_context, preference_2)

    updated_preferences = ContactSetting.get_contact_preferences(updated_flow_context)

    preference_2 = Glific.string_clean(preference_2)
    assert preference in updated_preferences
    assert preference_2 in updated_preferences
  end
end
