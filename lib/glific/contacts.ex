defmodule Glific.Contacts do
  @moduledoc """
  The Contacts context.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Contacts.Location,
    Repo
  }

  @doc """
  Returns the list of contacts.

  ## Examples

      iex> list_contacts()
      [%Contact{}, ...]

  """
  @spec list_contacts(map()) :: [Contact.t()]
  def list_contacts(args \\ %{}),
    do: Repo.list_filter(args, Contact, &opts_with/2, &filter_with/2)

  defp opts_with(query, opts) do
    Enum.reduce(opts, query, fn
      {:order, order}, query ->
        query |> order_by([c], {^order, fragment("lower(?)", c.name)})

      _, query ->
        query
    end)
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
    Enum.reduce(filter, query, fn
      {:name, name}, query ->
        from q in query, where: ilike(q.name, ^"%#{name}%")

      {:phone, phone}, query ->
        from q in query, where: ilike(q.phone, ^"%#{phone}%")

      {:status, status}, query ->
        from q in query, where: q.status == ^status

      {:provider_status, provider_status}, query ->
        from q in query, where: q.provider_status == ^provider_status
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
      optout_time: nil,
      status: :valid,
      provider_status: :valid
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
      status: :invalid,
      provider_status: :invalid,
      updated_at: DateTime.utc_now()
    })

    {:ok}
  end

  @doc """
  Check if we can send a message to the contact
  """
  @spec can_send_message_to?(Contact.t()) :: boolean()

  def can_send_message_to?(contact) do
    with true <- contact.status == :valid,
         true <- contact.provider_status == :valid,
         true <- Timex.diff(DateTime.utc_now(), contact.last_message_at, :hours) < 24,
         do: true
  end

  @doc """
  Check if we can send a hsm message to the contact
  """
  @spec can_send_hsm_message_to?(Contact.t()) :: boolean()
  def can_send_hsm_message_to?(contact) do
    with true <- contact.status == :valid,
         true <- contact.provider_status == :valid,
         true <- contact.optin_time != nil,
         true <- contact.optout_time == nil,
         do: true
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
end
