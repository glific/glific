defmodule Glific.Contacts do
  @moduledoc """
  The Contacts context.
  """
  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Repo, Search.Full}

  @doc """
  Returns the list of contacts.

  ## Examples

      iex> list_contacts()
      [%Contact{}, ...]

  """
  @spec list_contacts(map()) :: [Contact.t()]
  def list_contacts(args \\ %{}) do
    args
    |> Enum.reduce(Contact, fn
      {:opts, opts}, query ->
        query |> opts_with(opts)

      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.all()
  end

  defp opts_with(query, opts) do
    Enum.reduce(opts, query, fn
      {:order, order}, query ->
        query |> order_by([c], {^order, fragment("lower(?)", c.name)})

      {:limit, limit}, query ->
        query |> limit(^limit)

      {:offset, offset}, query ->
        query |> offset(^offset)
    end)
  end

  @doc """
  Return the count of contacts, using the same filter as list_contacts
  """
  @spec count_contacts(map()) :: integer
  def count_contacts(args \\ %{}) do
    args
    |> Enum.reduce(Contact, fn
      {:filter, filter}, query ->
        query |> filter_with(filter)
    end)
    |> Repo.aggregate(:count)
  end

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
  @spec upsert(map()) :: Contact.t()
  def upsert(attrs) do
    Repo.insert!(
      change_contact(%Contact{}, attrs),
      on_conflict: [set: [phone: attrs.phone]],
      conflict_target: :phone
    )
  end

  @doc """
  Full text search interface via Postgres
  """
  @spec search(String.t()) :: [Contact.t()]
  def search(term) do
    query = from(c in Contact)

    query
    |> Full.run(term)
    |> Repo.all()
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
  Check if this contact id is a new conatct
  """
  @spec contact_opted_in(String.t(), DateTime.t()) :: {:ok}
  def contact_opted_in(phone, utc_time) do
    # Still need to figure out how to do that in single query
    upsert(%{phone: phone, optin_time: utc_time})

    {:ok}
  end

  @doc """
  Check if we can send a message to the contact
  """
  @spec can_send_message_to?(Contact.t()) :: boolean()

  def can_send_message_to?(contact) do
    with true <- contact.provider_status == :valid,
         true <- Timex.diff(DateTime.utc_now(), contact.last_message_at, :hours) < 24,
         do: true
  end
end
