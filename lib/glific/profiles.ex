defmodule Glific.Profiles do
  @moduledoc """
  The Profiles context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.Action,
    Flows.ContactField,
    Flows.FlowContext,
    Messages,
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
  def delete_profile(%Profile{} = profile) do
    Repo.delete(profile)
  end

  @doc """
  Switches active profile of a contact

  ## Examples

      iex> switch_profile(contact)
      {:ok, %Profile{}}

  """
  @spec switch_profile(Contact.t(), String.t()) :: Contact.t()
  def switch_profile(contact, profile_index) do
    contact = Repo.preload(contact, [:active_profile])

    with {:ok, index} <- Glific.parse_maybe_integer(profile_index),
         {profile, _index} <- fetch_indexed_profile(contact, index),
         {:ok, _updated_contact} <-
           Contacts.update_contact(contact, %{active_profile_id: profile.id}),
         updated_contact <- Contacts.get_contact!(contact.id) do
      updated_contact
    else
      _ -> contact
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
      filter: %{contact_id: contact.id},
      opts: %{offset: 0, order: :asc},
      organization_id: contact.organization_id
    }
    |> list_profiles()
    |> Enum.with_index(1)
  end

  @doc """
    Handles flow action based on type of operation on Profile
  """
  @spec handle_flow_action(FlowContext.t(), Action.t(), String.t()) ::
          {FlowContext.t(), Message.t()}
  def handle_flow_action(context, action, "Switch Profile") do
    value = ContactField.parse_contact_field_value(context, action.value)

    with contact <- switch_profile(context.contact, value),
         context <- Map.put(context, :contact, contact) do
      contact = Repo.preload(contact, [:active_profile])

      Contacts.capture_history(context.contact.id, :profile_switched, %{
        event_label: "Switched profile to #{contact.active_profile.name}",
        event_meta: %{
          method: "switched profile via flow: #{context.flow.name}"
        }
      })

      {context, Messages.create_temp_message(context.organization_id, "Success")}
    else
      _ ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  def handle_flow_action(context, action, "Create Profile") do
    attrs = %{
      name: ContactField.parse_contact_field_value(context, action.value["name"]),
      type: ContactField.parse_contact_field_value(context, action.value["type"]),
      contact_id: context.contact.id,
      language_id: context.contact.language_id,
      organization_id: context.contact.organization_id
    }

    case create_profile(attrs) do
      {:ok, _profile} ->
        {context, Messages.create_temp_message(context.organization_id, "Success")}

      {:error, _error} ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end
end
