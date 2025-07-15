defmodule Glific.Profiles do
  @moduledoc """
  The Profiles context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.Action,
    Flows.ContactField,
    Flows.FlowContext,
    Messages,
    Messages.Message,
    Profiles.Profile,
    Repo
  }

  @doc """
  Returns the list of profiles.

  ## Examples

      iex> list_profiles()
      [%Profile{}, ...]

  Get the list of profiles filtered by various search options
  """
  @spec list_profiles(map()) :: [Profile.t()]
  def list_profiles(args) do
    Repo.list_filter(args, Profile, &Repo.opts_with_name/2, &filter_with/2)
  end

  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:contact_id, contact_id}, query ->
        from(q in query, where: q.contact_id == ^contact_id)

      {:is_active, is_active}, query when is_boolean(is_active) ->
        from(q in query, where: q.is_active == ^is_active)

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single profile.

  Raises `Ecto.NoResultsError` if the Profile does not exist.

  ## Examples

      iex> get_profile!(123)
      %Profile{}

      iex> get_profile!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_profile!(integer) :: Profile.t()
  def get_profile!(id), do: Repo.get!(Profile, id)

  @doc """
  Creates a profile.

  ## Examples

      iex> create_profile(%{field: value})
      {:ok, %Profile{}}

      iex> create_profile(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_profile(map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def create_profile(attrs \\ %{}) do
    %Profile{}
    |> Profile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a profile.

  ## Examples

      iex> update_profile(profile, %{field: new_value})
      {:ok, %Profile{}}

      iex> update_profile(profile, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_profile(Profile.t(), map()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%Profile{} = profile, attrs) do
    profile
    |> Profile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a profile.

  ## Examples

      iex> delete_profile(profile)
      {:ok, %Profile{}}

      iex> delete_profile(profile)
      {:error, %Ecto.Changeset{}}

  """

  @spec delete_profile(Profile.t()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}

  def delete_profile(%Profile{is_default: true} = profile) do
    contact = Repo.preload(profile, :contact).contact
    Contacts.delete_contact(contact)
  end

  def delete_profile(%Profile{is_default: false} = profile) do
    Repo.delete(profile)
  end

  @doc """
  Switches active profile of a contact

  ## Examples

      iex> switch_profile(contact)
      {:ok, %Profile{}}

  """
  @spec switch_profile(Contact.t(), String.t()) :: {:ok, Contact.t()} | {:error, Contact.t()}
  def switch_profile(contact, profile_index) do
    contact = Repo.preload(contact, [:active_profile])

    Logger.info(
      "Switching Profile for org_id: #{contact.organization_id} contact_id: #{contact.id} with profile_index: #{profile_index}"
    )

    with {:ok, index} <- Glific.parse_maybe_integer(profile_index),
         {profile, _index} <- fetch_indexed_profile(contact, index),
         {:ok, updated_contact} <-
           Contacts.update_contact(contact, %{
             active_profile_id: profile.id,
             language_id: profile.language_id,
             fields: profile.fields
           }) do
      contact =
        updated_contact
        |> Repo.preload([:active_profile], force: true)

      {:ok, contact}
    else
      _ -> {:error, contact}
    end
  end

  @spec fetch_indexed_profile(Contact.t(), integer) :: {Profile.t(), integer} | nil
  defp fetch_indexed_profile(contact, index) do
    contact
    |> get_indexed_profile()
    |> Enum.find(fn {_profile, profile_index} -> profile_index == index end)
  end

  @doc """
  Get a profile associated with a contact indexed and sorted in ascending order

  ## Examples

      iex> Glific.Profiles.get_indexed_profile(con)
      [{%Profile{}, 1}, {%Profile{}, 2}]
  """
  @spec get_indexed_profile(Contact.t()) :: [{any, integer}]
  def get_indexed_profile(contact) do
    %{
      filter: %{contact_id: contact.id, is_active: true},
      opts: %{offset: 0, order: :desc, order_with: :is_default},
      organization_id: contact.organization_id
    }
    |> list_profiles()
    |> Enum.with_index(1)
  end

  @doc """
    Handles flow action based on type of operation on Profile
  """
  @spec handle_flow_action(atom() | nil, FlowContext.t(), Action.t()) ::
          {FlowContext.t(), Message.t()}
  def handle_flow_action(:switch_profile, context, action) do
    value = ContactField.parse_contact_field_value(context, action.value)

    with {:ok, contact} <- switch_profile(context.contact, value),
         context <- Map.put(context, :contact, contact) do
      Contacts.capture_history(context.contact.id, :profile_switched, %{
        event_label: "Switched profile to #{contact.active_profile.name}",
        event_meta: %{
          method: "Switched profile via flow: #{context.flow.name}"
        }
      })

      {context, Messages.create_temp_message(context.organization_id, "Success")}
    else
      _ ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  def handle_flow_action(:create_profile, context, action) do
    attrs = %{
      name: ContactField.parse_contact_field_value(context, action.value["name"]),
      type: ContactField.parse_contact_field_value(context, action.value["type"]),
      contact_id: context.contact.id,
      language_id: context.contact.language_id,
      organization_id: context.contact.organization_id
    }

    with {:ok, default_profile} <- maybe_setup_default_profile(attrs, context),
         {:ok, _profile} <- create_profile(attrs) do
      maybe_switch_to_default_profile(context, action, default_profile)
    else
      {:error, _error} ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  def handle_flow_action(:deactivate_profile, context, action) do
    value =
      ContactField.parse_contact_field_value(context, action.value)

    attrs = %{
      contact_id: context.contact.id,
      language_id: context.contact.language_id,
      organization_id: context.contact.organization_id
    }

    with {:ok, default_profile} <- maybe_setup_default_profile(attrs, context),
         {:ok, index} <- Glific.parse_maybe_integer(value),
         {profile, _index} <- fetch_indexed_profile(context.contact, index),
         false <- deactivating_default_profile?(default_profile, profile),
         {:ok, _updated_profile} <- update_profile(profile, %{is_active: false}) do
      handle_deactivation_flow(context, action, default_profile, profile)
    else
      # we don't deactivate the default profile, but still return success
      # because the default profile is treated as a contact.
      true ->
        {context, Messages.create_temp_message(context.organization_id, "Success")}

      _error ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  def handle_flow_action(_profile_type, context, _action) do
    {context, Messages.create_temp_message(context.organization_id, "Failure")}
  end

  @spec maybe_switch_to_default_profile(FlowContext.t(), Action.t(), Profile.t()) ::
          {FlowContext.t(), Message.t()}
  defp maybe_switch_to_default_profile(context, action, default_profile) do
    contact = context.contact

    if contact.active_profile_id do
      {context, Messages.create_temp_message(context.organization_id, "Success")}
    else
      profile_action = get_action_with_index(context, action, default_profile)
      handle_flow_action(:switch_profile, context, profile_action)
    end
  end

  @spec get_action_with_index(FlowContext.t(), Action.t(), map()) :: Action.t()
  defp get_action_with_index(context, action, profile) do
    indexed_profile = get_indexed_profile(context.contact)

    {_profile, profile_index} =
      Enum.find(indexed_profile, fn {index_profile, _index} ->
        index_profile.id == profile.id
      end)

    Map.put(action, :value, to_string(profile_index))
  end

  @spec maybe_setup_default_profile(map(), map()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  defp maybe_setup_default_profile(attrs, context) do
    case Repo.get_by(Profile, contact_id: context.contact.id, is_default: true) do
      nil ->
        setup_default_profile(context.contact, attrs)

      profile ->
        {:ok, profile}
    end
  end

  # Create the default profile for the user:
  # 1. To preserve the original `contact_fields` of the contact. These fields
  #    are overwritten when switching to other profiles.
  # 2. To allow the user to switch back to the original contact state,
  #    instead of being locked into a specific profile.
  @spec setup_default_profile(Contact.t(), map()) :: {:ok, Profile.t()}
  defp setup_default_profile(contact, attrs) do
    args = %{
      filter: %{contact_id: contact.id},
      opts: %{offset: 0, order: :asc, order_with: :inserted_at},
      organization_id: contact.organization_id
    }

    case list_profiles(args) do
      [] ->
        attrs
        |> Map.put(:name, contact.name)
        |> Map.put(:is_default, true)
        |> Map.put(:fields, contact.fields)
        |> create_profile()

      [first_profile | _] ->
        update_profile(first_profile, %{is_default: true})
    end
  end

  @spec deactivating_default_profile?(Profile.t(), Profile.t()) :: boolean()
  defp deactivating_default_profile?(%Profile{id: profile_id}, %Profile{id: profile_id}),
    do: true

  defp deactivating_default_profile?(_, _), do: false

  @spec handle_deactivation_flow(FlowContext.t(), Action.t(), map(), map()) ::
          {FlowContext.t(), Message.t()}
  defp handle_deactivation_flow(context, action, default_profile, current_profile) do
    active_profile_id = context.contact.active_profile_id

    if active_profile_id == current_profile.id do
      profile_action = get_action_with_index(context, action, default_profile)
      handle_flow_action(:switch_profile, context, profile_action)
    else
      {context, Messages.create_temp_message(context.organization_id, "Success")}
    end
  end
end
