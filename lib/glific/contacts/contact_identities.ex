defmodule Glific.Contacts.ContactIdentities do
  @moduledoc """
  Internal to `Glific.Contacts`, which is the only module that calls it. Reads and writes
  `Glific.Contacts.ContactIdentity` rows: a contact's identities on each channel.

  It never calls back into `Glific.Contacts`.

  A `:whatsapp` identity mirrors `contacts.phone` and is kept in step with it by the contact write
  paths. It also holds a copy of the contact's consent and session state, written alongside the
  `contacts` columns, which stay the source of truth. A `:web` identity is a username issued by an NGO's own system, or the phone of a contact
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

  @type changes :: %{optional(atom()) => any()}

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
  Adds to `multi` the insert of the identity for the contact its `:contact` step inserted; a WhatsApp
  one also holds the contact's consent and session state.
  """
  @spec insert_identity(Multi.t(), MessageChannel.t(), String.t() | nil) :: Multi.t()
  def insert_identity(multi, channel, identifier) do
    Multi.insert(
      multi,
      :identity,
      fn %{contact: contact} ->
        identity_changeset(contact, channel, identifier, contact_identity_attrs(contact, channel))
      end,
      if(channel == :whatsapp, do: whatsapp_insert_opts(), else: [])
    )
  end

  @doc """
  Moves the contact's WhatsApp identity to its current phone, creating one when it has none.
  """
  @spec move_whatsapp_identity_to_phone(Contact.t()) :: :ok
  def move_whatsapp_identity_to_phone(%Contact{phone: phone}) when phone in [nil, ""], do: :ok

  def move_whatsapp_identity_to_phone(%Contact{phone: phone} = contact) do
    case whatsapp_identity_id(contact) do
      nil ->
        contact
        |> identity_changeset(:whatsapp, phone, contact_identity_attrs(contact, :whatsapp))
        |> Repo.insert(whatsapp_insert_opts())

      identity_id ->
        rename_whatsapp_identity(identity_id, contact)
    end

    :ok
  end

  @spec whatsapp_identity_id(Contact.t()) :: non_neg_integer() | nil
  defp whatsapp_identity_id(%Contact{id: contact_id}) do
    from(i in ContactIdentity,
      where: i.channel == :whatsapp and i.contact_id == ^contact_id,
      limit: 1,
      select: i.id
    )
    |> Repo.one()
  end

  # A number another identity already holds is left alone rather than raising on the unique index.
  @spec rename_whatsapp_identity(non_neg_integer(), Contact.t()) :: {non_neg_integer(), nil}
  defp rename_whatsapp_identity(identity_id, %Contact{
         organization_id: organization_id,
         phone: phone
       }) do
    taken =
      from(i in ContactIdentity,
        where:
          i.organization_id == ^organization_id and i.channel == :whatsapp and
            i.identifier == ^phone and i.id != ^identity_id
      )

    from(i in ContactIdentity, where: i.id == ^identity_id and not exists(subquery(taken)))
    |> Repo.update_all(set: [identifier: phone, updated_at: DateTime.utc_now()])
  end

  @doc """
  Copies the consent and session fields among `changes` onto the contact's WhatsApp identity, if it has one.
  """
  @spec copy_state_to_whatsapp_identity(Contact.t(), changes()) :: :ok
  def copy_state_to_whatsapp_identity(%Contact{phone: phone}, _changes) when phone in [nil, ""],
    do: :ok

  def copy_state_to_whatsapp_identity(%Contact{id: contact_id, phone: phone}, changes) do
    set =
      changes
      |> identity_state()
      |> Map.put(:updated_at, DateTime.utc_now())

    from(i in ContactIdentity,
      where: i.contact_id == ^contact_id and i.channel == :whatsapp and i.identifier == ^phone
    )
    |> Repo.update_all(set: Map.to_list(set))

    :ok
  end

  @doc """
  Sets `bsp_status` on the WhatsApp identities of the contacts `Contacts.set_session_status/2` updates.
  """
  @spec set_bsp_status([non_neg_integer()], boolean(), atom(), DateTime.t()) :: :ok
  def set_bsp_status(contact_ids, opted_in?, bsp_status, now) do
    from(i in ContactIdentity,
      join: c in assoc(i, :contact),
      where: i.channel == :whatsapp and i.contact_id in ^contact_ids,
      where: ^optin_time_filter(opted_in?)
    )
    |> Repo.update_all([set: [bsp_status: bsp_status, updated_at: now]],
      skip_organization_id: true
    )

    :ok
  end

  @spec optin_time_filter(boolean()) :: Ecto.Query.dynamic_expr()
  defp optin_time_filter(true), do: dynamic([i, c], not is_nil(c.optin_time))
  defp optin_time_filter(false), do: dynamic([i, c], is_nil(c.optin_time))

  @doc """
  Records opt-in on the contact's identity on `channel` unless it is already opted in.
  """
  @spec record_optin(non_neg_integer(), MessageChannel.t(), String.t(), DateTime.t(), String.t()) ::
          :recorded | :already_opted_in
  def record_optin(contact_id, channel, identifier, utc_time, method) do
    identifier = lookup_key(channel, identifier)

    # In the UPDATE itself rather than a read before it, so two concurrent sign-ins cannot both record.
    {updated, _rows} =
      from(i in ContactIdentity,
        where:
          i.contact_id == ^contact_id and i.channel == ^channel and i.identifier == ^identifier,
        where: i.optin_status == false
      )
      |> Repo.update_all(
        set: [
          optin_time: DateTime.truncate(utc_time, :second),
          optin_status: true,
          optin_method: method,
          optout_time: nil,
          optout_method: nil,
          updated_at: DateTime.utc_now()
        ]
      )

    if updated > 0, do: :recorded, else: :already_opted_in
  end

  @doc """
  Whether any of the contact's identities on `channel` holds an opt-in.
  """
  @spec opted_in?(Contact.t(), MessageChannel.t()) :: boolean()
  def opted_in?(%Contact{id: nil}, _channel), do: false

  def opted_in?(%Contact{id: contact_id}, channel) do
    from(i in ContactIdentity,
      where: i.contact_id == ^contact_id and i.channel == ^channel and i.optin_status == true
    )
    |> Repo.exists?()
  end

  @doc """
  Whether a contact changeset's changes touch what a WhatsApp identity holds: the phone or the state.
  """
  @spec whatsapp_changes?(changes()) :: boolean()
  def whatsapp_changes?(changes),
    do:
      Enum.any?(
        Map.keys(changes),
        &(&1 == :phone or &1 in ContactIdentity.consent_and_session_fields())
      )

  @doc """
  Bulk-inserts the WhatsApp identity, with its consent and session state, of each saved contact row.
  """
  @spec insert_whatsapp_identities([map()], non_neg_integer()) :: :ok
  def insert_whatsapp_identities(rows, organization_id) do
    now = DateTime.utc_now()

    rows
    |> Stream.filter(&(is_binary(&1.phone) and &1.phone != ""))
    |> Stream.map(fn row ->
      row
      |> contact_identity_attrs(:whatsapp)
      |> Map.merge(%{
        contact_id: row.id,
        organization_id: organization_id,
        channel: :whatsapp,
        identifier: row.phone,
        inserted_at: now,
        updated_at: now
      })
    end)
    |> Stream.chunk_every(@insert_chunk_size)
    |> Enum.each(
      &Repo.insert_all(ContactIdentity, &1,
        on_conflict: replace_state_of_same_contact(),
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
      {:ok, _identity} ->
        {:ok, contact}

      {:error, changeset} ->
        if identifier_taken?(changeset) and holds_web_identifier?(contact, identifier),
          do: {:ok, contact},
          else: {:error, changeset}
    end
  end

  @spec holds_web_identifier?(Contact.t(), String.t()) :: boolean()
  defp holds_web_identifier?(%Contact{id: contact_id}, identifier) do
    match?({:ok, %Contact{id: ^contact_id}}, fetch_contact(:web, identifier))
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

  @spec identity_changeset(Contact.t(), MessageChannel.t(), String.t(), map()) ::
          Ecto.Changeset.t()
  defp identity_changeset(contact, channel, identifier, state \\ %{}) do
    ContactIdentity.changeset(
      %ContactIdentity{},
      Map.merge(state, %{
        contact_id: contact.id,
        organization_id: contact.organization_id,
        channel: channel,
        identifier: identifier
      })
    )
  end

  @spec contact_identity_attrs(Contact.t() | map(), MessageChannel.t()) :: map()
  defp contact_identity_attrs(contact, :whatsapp), do: identity_state(contact)
  defp contact_identity_attrs(_contact, _channel), do: %{}

  # The identity's optin_status and bsp_status are NOT NULL. contacts.optin_status allows nil, and a
  # contact inserted without bsp_status holds nil in its struct, since Ecto does not read back the default.
  @spec identity_state(map()) :: map()
  defp identity_state(contact_or_changes) do
    contact_or_changes
    |> Map.take(ContactIdentity.consent_and_session_fields())
    |> Map.replace_lazy(:optin_status, &(&1 == true))
    |> Map.replace_lazy(:bsp_status, &(&1 || :none))
  end

  # allow_stale: a conflicting row another contact holds updates nothing, which Ecto would raise as stale.
  @spec whatsapp_insert_opts() :: keyword()
  defp whatsapp_insert_opts,
    do: [
      on_conflict: replace_state_of_same_contact(),
      conflict_target: conflict_target(),
      allow_stale: true
    ]

  # A row another contact still holds keeps its state: only its owner's insert may overwrite it.
  @spec replace_state_of_same_contact() :: Ecto.Query.t()
  defp replace_state_of_same_contact do
    from(i in ContactIdentity,
      where: i.contact_id == fragment("EXCLUDED.contact_id"),
      update: [
        set: [
          optin_time: fragment("EXCLUDED.optin_time"),
          optin_status: fragment("EXCLUDED.optin_status"),
          optin_method: fragment("EXCLUDED.optin_method"),
          optout_time: fragment("EXCLUDED.optout_time"),
          optout_method: fragment("EXCLUDED.optout_method"),
          bsp_status: fragment("EXCLUDED.bsp_status"),
          last_message_at: fragment("EXCLUDED.last_message_at"),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ]
    )
  end

  @spec conflict_target() :: [atom()]
  defp conflict_target, do: [:organization_id, :channel, :identifier]
end
