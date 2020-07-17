defmodule Glific.Flows.ContactSetting do
  @moduledoc """
  Since many of the functions set/update fields in contact and related tables, lets
  centralize all the code here for now
  """

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.FlowContext,
    Settings
  }

  @doc """
  Set the language for a contact
  """
  @spec set_contact_language(FlowContext.t(), String.t()) :: FlowContext.t()
  def set_contact_language(context, language) do
    # get the language id
    [language | _] = Settings.list_languages(%{label: language})
    {:ok, contact} = Contacts.update_contact(context.contact, %{language_id: language.id})
    Map.put(context, :contact, contact)
  end

  @doc """
  Set the name for a contact
  """
  @spec set_contact_name(FlowContext.t(), String.t()) :: FlowContext.t()
  def set_contact_name(context, name) do
    {:ok, contact} = Contacts.update_contact(context.contact, %{name: name})
    Map.put(context, :contact, contact)
  end

  @doc """
  Wrapper function for setting the contact preference, if preference is empty, it
  indicates to reset the preference
  """
  @spec set_contact_preference(FlowContext.t(), String.t()) :: FlowContext.t()
  def set_contact_preference(context, preference) do
    # first clean up the preference string
    preference = Glific.string_clean(preference)

    if preference == "",
      do: reset_contact_preference(context),
      else: add_contact_preference(context, preference)
  end

  @doc """
  Add a preference to a contact. For now, all preferences are stored under the
  settings map, with a sub-map of preferences. We expect to get more clarity on this soon
  """
  @spec add_contact_preference(FlowContext.t(), String.t(), boolean()) :: FlowContext.t()
  def add_contact_preference(context, preference, value \\ true)

  # reset the contact preference when explicitly asked to do so
  def add_contact_preference(context, preference, _value) when preference == "reset",
    do: reset_contact_preference(context)

  def add_contact_preference(context, preference, value) do
    contact_settings =
      if is_nil(context.contact.settings),
        do: %{"preferences" => %{}},
        else: context.contact.settings

    preferences =
      contact_settings
      |> Map.get("preferences", %{})
      |> Map.put(preference, value)

    {:ok, contact} =
      Contacts.update_contact(
        context.contact,
        %{settings: Map.put(contact_settings, "preferences", preferences)}
      )

    Map.put(context, :contact, contact)
  end

  @doc """
  Delete a preference from a contact. We actually dont really delete it, we just
  set the value to false, and hence turn it off
  """
  @spec delete_contact_preference(FlowContext.t(), String.t()) :: FlowContext.t()
  def delete_contact_preference(context, preference) do
    add_contact_preference(context, preference, false)
  end

  @doc """
  Get all the preferences for this contact
  """
  @spec get_contact_preferences(FlowContext.t()) :: [String.t()]
  def get_contact_preferences(%FlowContext{contact: %Contact{settings: setting}})
      when is_nil(setting),
      do: []

  def get_contact_preferences(contact: %FlowContext{contact: %Contact{settings: setting}}),
    do:
      Enum.reduce(
        Map.get(setting, "preferences", %{}),
        [],
        fn {k, v}, acc -> if v, do: [k | acc], else: acc end
      )

  @doc """
  Reset the preferences for a contact.
  """
  @spec reset_contact_preference(FlowContext.t()) :: FlowContext.t()
  def reset_contact_preference(context) do
    {:ok, contact} =
      Contacts.update_contact(
        context.contact,
        %{settings: %{"preferences" => %{}}}
      )

    Map.put(context, :contact, contact)
  end
end
