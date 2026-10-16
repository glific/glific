defmodule Glific.Contacts.ContactIdentities do
  @moduledoc """
  Internal to `Glific.Contacts`, which is the only module that calls it. Reads and writes
  `Glific.Contacts.ContactIdentity` rows: the logins a contact can be reached or recognised by.

  It never calls back into `Glific.Contacts`.

  A `:whatsapp` identity mirrors `contacts.phone` and is kept in step with it by the contact write
  paths. A `:web` identity is an opaque username issued by an NGO's own system, and is never a
  phone: a contact signing in with a one-time code is found by `contacts.phone`, and recording it
  here would let an NGO username equal to that phone number reach the same conversation.
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

    from(i in ContactIdentity,
      where: i.channel == :whatsapp and i.contact_id == ^contact_id and i.identifier != ^phone
    )
    |> Repo.delete_all()

    contact
    |> identity_changeset(:whatsapp, phone)
    |> Repo.insert(ignore_conflict_opts())

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
