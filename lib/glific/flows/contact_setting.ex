defmodule Glific.Flows.ContactSetting do
  @moduledoc """
  Since many of the functions set/update fields in contact and related tables, lets
  centralize all the code here for now
  """

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.FlowContext,
    Profiles,
    Repo,
    Settings
  }

  @doc """
  Set the language for a contact
  """
  @spec set_contact_language(FlowContext.t(), String.t()) :: FlowContext.t()
  def set_contact_language(context, language) do
    # get the language id
    language
    |> fix_language()
    |> Settings.get_language_by_label_or_locale()
    |> case do
      [language | _] ->
        {:ok, contact} = Contacts.update_contact(context.contact, %{language_id: language.id})

        {:ok, _} =
          Contacts.capture_history(contact, :contact_language_updated, %{
            event_label: "Changed contact language to #{language.label}",
            event_meta: %{
              language: %{
                id: language.id,
                label: language.label,
                old_language: context.contact.language_id
              },
              flow: %{
                id: context.flow.id,
                name: context.flow.name,
                uuid: context.flow.uuid
              }
            }
          })

        # update profile languange if active profile is set for a contact
        maybe_update_profile_language(contact, language.id)

        Map.put(context, :contact, contact)

      [] ->
        raise("Error! No language found with label #{inspect(language)}")
    end
  end

  @doc """
  Update profile language if there is an active profile id set
  """
  @spec maybe_update_profile_language(Contact.t(), non_neg_integer()) ::
          Contact.t()
  def maybe_update_profile_language(
        %{active_profile_id: active_profile_id} = contact,
        language_id
      )
      when is_integer(active_profile_id) do
    with {:ok, profile} <- Repo.fetch_by(Profiles.Profile, %{id: active_profile_id}) do
      Profiles.update_profile(profile, %{language_id: language_id})
    end

    contact
  end

  def maybe_update_profile_language(contact, _language_id), do: contact

  @spec fix_language(String.t()) :: String.t()
  defp fix_language("en_US"), do: "en"
  defp fix_language(language), do: language

  @doc """
  Set the name for a contact
  """
  @spec set_contact_name(FlowContext.t(), String.t()) :: FlowContext.t()
  def set_contact_name(context, name) do
    {:ok, contact} = Contacts.update_contact(context.contact, %{name: name})

    {:ok, _} =
      Contacts.capture_history(contact, :contact_name_updated, %{
        event_label: "contact name changed to #{name}",
        event_meta: %{
          flow: %{
            id: context.flow.id,
            name: context.flow.name,
            uuid: context.flow.uuid
          },
          name: %{
            old_name: context.contact.name,
            new_name: name
          }
        }
      })

    Map.put(context, :contact, contact)
  end

  @doc """
  Wrapper function for setting the contact preference, if preference is empty, it
  indicates to reset the preference
  """
  @spec set_contact_preference(FlowContext.t(), String.t() | nil) :: FlowContext.t()
  def set_contact_preference(context, preference) do
    if preference == "" or is_nil(preference),
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
    # first clean up the preference string
    preference = Glific.string_clean(preference)

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

  def get_contact_preferences(%FlowContext{contact: %Contact{settings: setting}}),
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
