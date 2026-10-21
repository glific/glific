defmodule Glific.Contacts.ContactIdentities do
  @moduledoc """
  Internal to `Glific.Contacts`, which is the only module that calls it. Reads and writes
  `Glific.Contacts.ContactIdentity` rows: a contact's identities on each channel.

  It never calls back into `Glific.Contacts`.

  A `:whatsapp` identity mirrors `contacts.phone` and is kept in step with it by the contact write
  paths. Each identity holds the contact's consent and session state on its channel: opt-in, opt-out, and for
  WhatsApp the BSP status and the last inbound message. A `:web` identity is a username issued by an NGO's own system, or the phone of a contact
  that verified it with a one-time code.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.MessageChannel,
    Repo
  }

  @insert_chunk_size 1_000

  @channel_fields [
    :optin_time,
    :optin_status,
    :optin_method,
    :optout_time,
    :optout_method,
    :bsp_status,
    :last_message_at
  ]

  @time_fields [:optin_time, :optout_time, :last_message_at]

  @doc """
  Splits `attrs` into the consent and session fields an identity holds and everything else.
  """
  @spec split_channel_fields(map()) :: {map(), map()}
  def split_channel_fields(attrs), do: Map.split(attrs, @channel_fields)

  @doc """
  Reads the consent and session fields of each contact's identity on `channel` from the database, in one query,
  and sets them on the contacts. A contact without the identity gets the defaults: not opted in, BSP status
  `:none`, no times.
  """
  @spec load_channel_fields([Contact.t()], MessageChannel.t()) :: [Contact.t()]
  def load_channel_fields([], _channel), do: []

  def load_channel_fields(contacts, channel) do
    contact_ids = Enum.map(contacts, & &1.id)
    organization_ids = contacts |> Enum.map(& &1.organization_id) |> Enum.uniq()

    # The contacts' own organizations scope the read, so it is safe in a process with no organization set,
    # such as a GraphQL batch. The lowest id wins where a contact has several identities on a channel.
    found =
      from(i in ContactIdentity,
        where: i.contact_id in ^contact_ids and i.organization_id in ^organization_ids,
        where: i.channel == ^channel,
        order_by: [desc: i.id]
      )
      |> Repo.all(skip_organization_id: true)
      |> Map.new(&{&1.contact_id, &1})

    Enum.map(contacts, fn contact ->
      fields = found |> Map.get(contact.id, %ContactIdentity{}) |> Map.take(@channel_fields)
      struct(contact, fields)
    end)
  end

  @doc """
  Left-joins each contact's identity on `channel` as the named binding `:identity`. The contact is the query's
  binding named `contact_binding`; a query that already has the join is returned as it is.
  """
  @spec join_identity(Ecto.Queryable.t(), MessageChannel.t(), atom()) :: Ecto.Query.t()
  def join_identity(query, channel, contact_binding \\ :contact) do
    query = Ecto.Queryable.to_query(query)

    if has_named_binding?(query, :identity),
      do: query,
      else:
        join(query, :left, [], i in ContactIdentity,
          as: :identity,
          on: i.contact_id == field(as(^contact_binding), :id) and i.channel == ^channel
        )
  end

  @doc """
  Applies `changes` to the contacts' identities on `channel` and marks the contacts updated, which
  BigQuery's sync keys on, unless `touch: false`. A WhatsApp identity that does not exist yet is created from
  the contact's phone.
  """
  @spec update_channel_fields([Contact.t()], MessageChannel.t(), map(), keyword()) :: :ok
  def update_channel_fields(contacts, channel, changes, opts \\ [])
  def update_channel_fields([], _channel, _changes, _opts), do: :ok

  def update_channel_fields(_contacts, _channel, changes, _opts) when map_size(changes) == 0,
    do: :ok

  def update_channel_fields(contacts, channel, changes, opts) do
    now = DateTime.utc_now()
    contact_ids = Enum.map(contacts, & &1.id)
    set = Map.to_list(normalize(changes)) ++ [updated_at: now]

    if Keyword.get(opts, :touch, true),
      do:
        Repo.update_all(from(c in Contact, where: c.id in ^contact_ids), [set: [updated_at: now]],
          skip_organization_id: true
        )

    identities =
      from(i in ContactIdentity, where: i.contact_id in ^contact_ids and i.channel == ^channel)

    {updated, _rows} = Repo.update_all(identities, [set: set], skip_organization_id: true)

    if channel == :whatsapp and updated < length(contacts) do
      contacts
      |> Enum.group_by(& &1.organization_id)
      |> Enum.each(fn {organization_id, group} ->
        insert_whatsapp_identities(group, organization_id)
      end)

      Repo.update_all(identities, [set: set], skip_organization_id: true)
    end

    :ok
  end

  @spec normalize(map()) :: map()
  defp normalize(changes) do
    Map.new(changes, fn
      {field, %DateTime{} = time} when field in @time_fields ->
        {field, DateTime.truncate(time, :second)}

      pair ->
        pair
    end)
  end

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
  Adds to `multi` the insert of the identity for the contact its `:contact` step inserted.
  """
  @spec insert_identity(Multi.t(), MessageChannel.t(), String.t() | nil) :: Multi.t()
  def insert_identity(multi, channel, identifier) do
    Multi.insert(
      multi,
      :identity,
      fn %{contact: contact} -> identity_changeset(contact, channel, identifier) end,
      identity_insert_opts(channel)
    )
  end

  @doc """
  Makes the contact's WhatsApp identity its current phone, replacing older or stale rows for it.
  """
  @spec set_whatsapp_identity(Contact.t()) :: :ok
  def set_whatsapp_identity(%Contact{phone: phone}) when phone in [nil, ""], do: :ok

  def set_whatsapp_identity(%Contact{id: contact_id, phone: phone} = contact) do
    delete_stale_whatsapp_identities(contact)
    carry_state_to_phone(contact)

    from(i in ContactIdentity,
      where: i.channel == :whatsapp and i.contact_id == ^contact_id and i.identifier != ^phone
    )
    |> Repo.delete_all()

    contact
    |> identity_changeset(:whatsapp, phone)
    |> Repo.insert(ignore_conflict_opts())

    :ok
  end

  # A changed phone keeps its consent and session state: the oldest previous row becomes the row of the new phone.
  @spec carry_state_to_phone(Contact.t()) :: :ok
  defp carry_state_to_phone(%Contact{id: contact_id, phone: phone}) do
    identities =
      from(i in ContactIdentity, where: i.channel == :whatsapp and i.contact_id == ^contact_id)

    with false <- Repo.exists?(from(i in identities, where: i.identifier == ^phone)),
         [identity_id | _] <-
           Repo.all(
             from(i in identities, where: i.identifier != ^phone, order_by: i.id, select: i.id)
           ) do
      Repo.update_all(from(i in ContactIdentity, where: i.id == ^identity_id),
        set: [identifier: phone, updated_at: DateTime.utc_now()]
      )
    end

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
  Bulk-inserts the WhatsApp identity of each saved contact row, in batches, skipping existing ones.
  """
  @spec insert_whatsapp_identities([map()], non_neg_integer()) :: :ok
  def insert_whatsapp_identities(rows, organization_id) do
    now = DateTime.utc_now()

    rows
    |> Stream.filter(&(is_binary(&1.phone) and &1.phone != ""))
    |> Stream.map(fn row ->
      %{
        contact_id: row.id,
        organization_id: organization_id,
        channel: :whatsapp,
        identifier: row.phone,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Stream.chunk_every(@insert_chunk_size)
    |> Enum.each(
      &Repo.insert_all(ContactIdentity, &1,
        on_conflict: :nothing,
        conflict_target: conflict_target(),
        skip_organization_id: true
      )
    )
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
  Records the contact's first opt-in on the identity it logs in with, keeping its time and method for good. Once the
  identity has opted in, or opted in and out, nothing changes: a later login never clears an opt-out.
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

    case Repo.one(from(i in identity, select: {i.id, i.optin_time})) do
      nil -> {:error, :not_found}
      {_id, %DateTime{}} -> {:ok, :unchanged}
      {_id, nil} -> {:ok, set_optin(identity, method, optin_time)}
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
        where: is_nil(i.optin_time),
        update: [
          set: [
            optin_time: ^optin_time,
            optin_status: true,
            optin_method: ^method,
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

  @spec identity_insert_opts(MessageChannel.t()) :: keyword()
  defp identity_insert_opts(:web), do: []

  defp identity_insert_opts(_channel), do: ignore_conflict_opts()

  @spec ignore_conflict_opts() :: keyword()
  defp ignore_conflict_opts, do: [on_conflict: :nothing, conflict_target: conflict_target()]

  @spec conflict_target() :: [atom()]
  defp conflict_target, do: [:organization_id, :channel, :identifier]
end
