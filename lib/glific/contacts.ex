defmodule Glific.Contacts do
  @moduledoc """
  The Contacts context.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Contacts.Location,
    Groups.ContactGroup,
    Repo,
    Tags.ContactTag
  }

  @doc """
  Returns the list of contacts.

  ## Examples

      iex> list_contacts()
      [%Contact{}, ...]

  """
  @spec list_contacts(map()) :: [Contact.t()]
  def list_contacts(args \\ %{}),
    do: Repo.list_filter(args, Contact, &Repo.opts_with_name/2, &filter_with/2)

  @doc """
  Get the list of contacts filtered by various search options
  Include contacts only if within list of groups
  Include contacts only if have list of tags
  """
  @spec search_contacts(map()) :: [Contact.t()]
  def search_contacts(args \\ %{}),
    do: Repo.list_filter(args, Contact, &Repo.opts_with_name/2, &search_filter/2)

  @spec search_filter(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp search_filter(query, filter) do
    query = Repo.filter_with(query, filter)

    query =
      Enum.reduce(filter, query, fn
        {:include_groups, group_ids}, query ->
          query
          |> join(:left, [c], cg in ContactGroup, on: c.id == cg.contact_id)
          |> where([c, cg], cg.group_id in ^group_ids)

        {:include_tags, tag_ids}, query ->
          query
          |> join(:left, [c], ct in ContactTag, on: c.id == ct.contact_id)
          |> where([c, ..., ct], ct.tag_id in ^tag_ids)
      end)

    query
    |> distinct([c], c.id)
  end

  @doc """
  Return the count of contacts, using the same filter as list_contacts
  """
  @spec count_contacts(map()) :: integer
  def count_contacts(args \\ %{}),
    do: Repo.count_filter(args, Contact, &filter_with/2)

  # codebeat:disable[ABC]
  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        from q in query, where: q.status == ^status

      {:provider_status, provider_status}, query ->
        from q in query, where: q.provider_status == ^provider_status

      _, query ->
        query
    end)
  end

  # codebeat:enable[ABC]

  @doc """
  Gets a single contact.

  Raises `Ecto.NoResultsError` if the Contact does not exist.

  ## Examples

      iex> get_contact!(123)
      %Contact{}

      iex> get_contact!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_contact!(integer) :: Contact.t()
  def get_contact!(id), do: Repo.get!(Contact, id)

  @doc """
  Creates a contact.

  ## Examples

      iex> create_contact(%{field: value})
      {:ok, %Contact{}}

      iex> create_contact(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_contact(attrs \\ %{}) do
    # Get the organization
    organization = Glific.Partners.Organization |> Ecto.Query.first() |> Repo.one()

    attrs = Map.put(attrs, :language_id, attrs[:language_id] || organization.default_language_id)

    %Contact{}
    |> Contact.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a contact.

  ## Examples

      iex> update_contact(contact, %{field: new_value})
      {:ok, %Contact{}}

      iex> update_contact(contact, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_contact(Contact.t(), map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def update_contact(%Contact{} = contact, attrs) do
    contact
    |> Contact.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a contact.

  ## Examples

      iex> delete_contact(contact)
      {:ok, %Contact{}}

      iex> delete_contact(contact)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_contact(Contact.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def delete_contact(%Contact{} = contact) do
    Repo.delete(contact)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contact changes.

  ## Examples

      iex> change_contact(contact)
      %Ecto.Changeset{data: %Contact{}}

  """
  @spec change_contact(Contact.t(), map()) :: Ecto.Changeset.t()
  def change_contact(%Contact{} = contact, attrs \\ %{}) do
    Contact.changeset(contact, attrs)
  end

  @doc """
  Gets or Creates a Contact based on the unique indexes in the table. If there is a match
  it returns the existing contact, else it creates a new one
  """
  @spec upsert(map()) :: {:ok, Contact.t()}
  def upsert(attrs) do
    # Get the organization
    organization = Glific.Partners.Organization |> Ecto.Query.first() |> Repo.one()
    # we keep this separate to avoid overwriting the language if already set by a contact
    # this will not appear in the set field of the on_conflict: clause below
    language = Map.put(%{}, :language_id, attrs[:language_id] || organization.default_language_id)

    contact =
      Repo.insert!(
        change_contact(%Contact{}, Map.merge(language, attrs)),
        on_conflict: [set: Enum.map(attrs, fn {key, value} -> {key, value} end)],
        conflict_target: :phone
      )

    {:ok, contact}
  end

  @doc """
  Check if this contact id is a new conatct
  """

  @spec is_new_contact(integer()) :: boolean()
  def is_new_contact(contact_id) do
    case Glific.Messages.Message
         |> where([c], c.contact_id == ^contact_id)
         |> where([c], c.flow == "outbound")
         |> Repo.all() do
      [] -> true
      _ -> false
    end
  end

  @doc """
  Update DB fields when contact opted in
  """
  @spec contact_opted_in(String.t(), DateTime.t()) :: {:ok}
  def contact_opted_in(phone, utc_time) do
    upsert(%{
      phone: phone,
      optin_time: utc_time,
      last_message_at: utc_time,
      optout_time: nil,
      status: :valid,
      provider_status: :session_and_hsm,
      updated_at: DateTime.utc_now()
    })

    {:ok}
  end

  @doc """
  Update DB fields when contact opted out
  """
  @spec contact_opted_out(String.t(), DateTime.t()) :: {:ok}
  def contact_opted_out(phone, utc_time) do
    upsert(%{
      phone: phone,
      optout_time: utc_time,
      optin_time: nil,
      status: :invalid,
      provider_status: :none,
      updated_at: DateTime.utc_now()
    })

    {:ok}
  end

  @doc """
  Check if we can send a message to the contact
  """

  @spec can_send_message_to?(Contact.t()) :: boolean()
  def can_send_message_to?(contact), do: can_send_message_to?(contact, false)

  @doc false
  @spec can_send_message_to?(Contact.t(), boolean()) :: boolean()
  def can_send_message_to?(contact, true = _is_hsm) do
    with :valid <- contact.status,
         true <- contact.provider_status in [:session_and_hsm, :hsm],
         true <- contact.optin_time != nil do
      true
    else
      _ -> false
    end
  end

  @doc """
  Check if we can send a session message to the contact
  """
  def can_send_message_to?(contact, _is_hsm) do
    with :valid <- contact.status,
         true <- contact.provider_status in [:session_and_hsm, :session],
         true <- Glific.in_past_time(contact.last_message_at, :hours, 24) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Get contact's current location
  """
  @spec contact_location(Contact.t()) :: {:ok, Location.t()}
  def contact_location(contact) do
    location =
      Location
      |> where([l], l.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    {:ok, location}
  end

  @doc """
  Creates a location.

  ## Examples
      iex> Glific.Contacts.create_location(%{name: value})
      {:ok, %Glific.Contacts.Location{}}

      iex> Glific.Contacts.create_location(%{bad_field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_location(map()) :: {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  def create_location(attrs \\ %{}) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Set session status for opted in and opted out contacts
  """
  @spec set_session_status(Contact.t(), atom()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def set_session_status(contact, :none = _status) do
    if is_nil(contact.optin_time),
      do: update_contact(contact, %{provider_status: :none}),
      else: update_contact(contact, %{provider_status: :hsm})
  end

  def set_session_status(contact, :session = _status) do
    if is_nil(contact.optin_time),
      do: update_contact(contact, %{provider_status: :session}),
      else: update_contact(contact, %{provider_status: :session_and_hsm})
  end
end
