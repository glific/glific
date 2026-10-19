defmodule Glific.Contacts.ContactIdentities do
  @moduledoc """
  Internal to `Glific.Contacts`, which is the only module that calls it. Reads and writes
  `Glific.Contacts.ContactIdentity` rows: a contact's identities on each channel.

  It never calls back into `Glific.Contacts`.

  A `:whatsapp` identity mirrors `contacts.phone` and is kept in step with it by the contact write
  paths; it also holds the contact's WhatsApp state (see `Glific.Contacts.WhatsAppState`). A `:web`
  identity is a username issued by an NGO's own system, or the phone of a contact that verified it
  with a one-time code, and holds the contact's web consent.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Contacts.WhatsAppState,
    Enums.MessageChannel,
    Repo
  }

  @doc """
  The contact holding an identity; web usernames are case-insensitive, WhatsApp ones must equal its phone.
  """
  @spec fetch_contact(MessageChannel.t(), String.t()) ::
          {:ok, Contact.t()} | {:error, :not_found}
  def fetch_contact(channel, identifier) do
    identifier = lookup_key(channel, identifier)

    query =
      from(i in ContactIdentity,
        join: c in assoc(i, :contact),
        where: i.channel == ^channel and i.identifier == ^identifier,
        where: ^identifier_matches_phone(channel),
        select: c
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  @doc """
  The ids of an organization's contacts with a web identity, optionally matching a `LIKE` pattern.
  """
  @spec web_contact_ids_query(non_neg_integer(), String.t() | nil) :: Ecto.Query.t()
  def web_contact_ids_query(organization_id, like_pattern \\ nil) do
    # Repo scoping skips subqueries, so the organization is filtered here.
    from(i in ContactIdentity,
      where: i.organization_id == ^organization_id and i.channel == :web,
      where: ^username_matches(like_pattern),
      select: i.contact_id
    )
  end

  @spec username_matches(String.t() | nil) :: Ecto.Query.dynamic_expr()
  defp username_matches(nil), do: dynamic(true)
  defp username_matches(pattern), do: dynamic([i], like(i.identifier, ^pattern))

  @doc """
  Adds to `multi` the identity of the contact its `:contact` step inserted: a WhatsApp one is the
  contact's phone, seeded with the contact's current WhatsApp state, a web one is `identifier`.
  """
  @spec insert_identity(Multi.t(), MessageChannel.t(), String.t() | nil) :: Multi.t()
  def insert_identity(multi, :whatsapp, _identifier) do
    Multi.run(multi, :identity, fn _repo, %{contact: contact} ->
      {:ok, WhatsAppState.seed([contact.id])}
    end)
  end

  def insert_identity(multi, channel, identifier) do
    Multi.insert(multi, :identity, fn %{contact: contact} ->
      identity_changeset(contact, channel, identifier)
    end)
  end

  @doc """
  Makes the contact's WhatsApp identity its current phone, carrying its state over from the identity of
  its previous phone, or from the contact's own columns when it has none, and replacing stale rows.
  """
  @spec set_whatsapp_identity(Contact.t()) :: :ok
  def set_whatsapp_identity(%Contact{phone: phone}) when phone in [nil, ""], do: :ok

  def set_whatsapp_identity(%Contact{id: contact_id, phone: phone} = contact) do
    delete_stale_whatsapp_identities(contact)

    previous =
      from(i in ContactIdentity,
        where: i.channel == :whatsapp and i.contact_id == ^contact_id and i.identifier != ^phone,
        order_by: i.id,
        select: i.id
      )
      |> Repo.all()

    if previous != [] and not whatsapp_identity?(contact_id, phone),
      do: move_identity(hd(previous), phone)

    from(i in ContactIdentity,
      where: i.channel == :whatsapp and i.contact_id == ^contact_id and i.identifier != ^phone
    )
    |> Repo.delete_all()

    WhatsAppState.seed([contact_id])
  end

  @spec whatsapp_identity?(non_neg_integer(), String.t()) :: boolean()
  defp whatsapp_identity?(contact_id, phone),
    do:
      Repo.exists?(
        from(i in ContactIdentity,
          where: i.channel == :whatsapp and i.contact_id == ^contact_id and i.identifier == ^phone
        )
      )

  @spec move_identity(non_neg_integer(), String.t()) :: :ok
  defp move_identity(identity_id, phone) do
    Repo.update_all(from(i in ContactIdentity, where: i.id == ^identity_id),
      set: [identifier: phone, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  @spec delete_stale_whatsapp_identities(Contact.t()) :: non_neg_integer()
  defp delete_stale_whatsapp_identities(%Contact{id: contact_id, phone: phone}) do
    stale_ids =
      from(i in ContactIdentity,
        join: c in assoc(i, :contact),
        where: i.channel == :whatsapp and i.identifier == ^phone and i.contact_id != ^contact_id,
        where: is_nil(c.phone) or c.phone != ^phone,
        select: i.id
      )

    {deleted, _rows} =
      Repo.delete_all(from(i in ContactIdentity, where: i.id in subquery(stale_ids)))

    deleted
  end

  @doc """
  Adds a web username to a contact; one it already holds is accepted, one another contact holds is refused.
  """
  @spec add_web_identity(Contact.t(), String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def add_web_identity(contact, identifier) do
    case contact |> identity_changeset(:web, identifier) |> Repo.insert() do
      {:ok, _identity} -> {:ok, contact}
      {:error, changeset} -> ok_if_contact_has_identifier(contact, identifier, changeset)
    end
  end

  @doc """
  Records the contact's consent on the identity it logs in with. The first call sets the opt-in and keeps its
  time and method for good; a later call changes nothing, unless the contact had opted out, in which case it
  only clears the opt-out. Tells the caller whether anything changed, so it can decide whether to log history.
  """
  @spec record_optin(Contact.t(), MessageChannel.t(), String.t(), String.t() | nil, DateTime.t()) ::
          {:ok, :recorded | :unchanged} | {:error, :not_found}
  def record_optin(%Contact{id: contact_id}, channel, identifier, method, optin_time) do
    identity =
      from(i in ContactIdentity,
        where:
          i.contact_id == ^contact_id and i.channel == ^channel and
            i.identifier == ^lookup_key(channel, identifier)
      )

    case Repo.one(from(i in identity, select: {i.optin_time, i.optout_time})) do
      nil -> {:error, :not_found}
      {current, nil} when not is_nil(current) -> {:ok, :unchanged}
      _not_opted_in_or_opted_out -> {:ok, set_optin(identity, method, optin_time)}
    end
  end

  @doc """
  Records the contact's opt-out on the identity it logs in with; a second one changes nothing.
  """
  @spec record_optout(Contact.t(), MessageChannel.t(), String.t(), String.t(), DateTime.t()) ::
          {:ok, :recorded | :unchanged} | {:error, :not_found}
  def record_optout(%Contact{id: contact_id}, channel, identifier, method, optout_time) do
    optout_time = DateTime.truncate(optout_time, :second)

    identity =
      from(i in ContactIdentity,
        where:
          i.contact_id == ^contact_id and i.channel == ^channel and
            i.identifier == ^lookup_key(channel, identifier)
      )

    exists? = Repo.exists?(identity)

    {updated, _rows} =
      Repo.update_all(
        from(i in identity,
          where: is_nil(i.optout_time) or i.optin_status,
          update: [
            set: [
              optout_time: ^optout_time,
              optout_method: ^method,
              optin_status: false,
              updated_at: ^DateTime.utc_now()
            ]
          ]
        ),
        []
      )

    cond do
      updated > 0 -> {:ok, :recorded}
      exists? -> {:ok, :unchanged}
      true -> {:error, :not_found}
    end
  end

  @spec set_optin(Ecto.Query.t(), String.t() | nil, DateTime.t()) :: :recorded | :unchanged
  defp set_optin(identity, method, optin_time) do
    optin_time = DateTime.truncate(optin_time, :second)

    query =
      from(i in identity,
        where: is_nil(i.optin_time) or not is_nil(i.optout_time),
        update: [
          set: [
            optin_time:
              fragment("COALESCE(?, ?)", i.optin_time, type(^optin_time, :utc_datetime)),
            optin_status: true,
            optin_method:
              fragment(
                "CASE WHEN ? IS NULL THEN ? ELSE ? END",
                i.optin_time,
                type(^method, :string),
                i.optin_method
              ),
            optout_time: nil,
            optout_method: nil,
            updated_at: ^DateTime.utc_now()
          ]
        ]
      )

    case Repo.update_all(query, []) do
      {1, _rows} -> :recorded
      {0, _rows} -> :unchanged
    end
  end

  @spec ok_if_contact_has_identifier(Contact.t(), String.t(), Ecto.Changeset.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp ok_if_contact_has_identifier(contact, identifier, changeset) do
    with true <- identifier_taken?(changeset),
         {:ok, %Contact{id: id}} when id == contact.id <- fetch_contact(:web, identifier) do
      {:ok, contact}
    else
      _on_another_contact -> {:error, changeset}
    end
  end

  @doc """
  Whether an identity insert failed because the identifier already exists.
  """
  @spec identifier_taken?(Ecto.Changeset.t()) :: boolean()
  def identifier_taken?(changeset),
    do:
      Enum.any?(changeset.errors, fn {field, {_message, opts}} ->
        field == :identifier and opts[:constraint] == :unique
      end)

  @spec identifier_matches_phone(MessageChannel.t()) :: Ecto.Query.dynamic_expr()
  defp identifier_matches_phone(:whatsapp), do: dynamic([i, c], c.phone == i.identifier)
  defp identifier_matches_phone(_channel), do: dynamic(true)

  @spec lookup_key(MessageChannel.t(), String.t()) :: String.t()
  defp lookup_key(:web, identifier), do: String.downcase(identifier)
  defp lookup_key(_channel, identifier), do: identifier

  @spec identity_changeset(Contact.t(), MessageChannel.t(), String.t()) :: Ecto.Changeset.t()
  defp identity_changeset(contact, channel, identifier) do
    ContactIdentity.changeset(%ContactIdentity{}, %{
      contact_id: contact.id,
      organization_id: contact.organization_id,
      channel: channel,
      identifier: identifier
    })
  end
end
