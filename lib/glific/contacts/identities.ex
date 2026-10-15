defmodule Glific.Contacts.Identities do
  @moduledoc """
  Reads and writes `Glific.Contacts.ContactIdentity` rows: the logins a contact can be reached or
  recognised by.

  A `:whatsapp` identity mirrors `contacts.phone` and is kept in step with it by the contact write
  paths. A `:web` identity is an opaque username issued by an NGO's own system, and is never a
  phone: a contact signing in with a one-time code is found by `contacts.phone`, and recording it
  here would let an NGO username equal to that phone number reach the same conversation.
  `resolve_or_create/3` is how a first connect turns a username into a contact.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.MessageChannel,
    Partners,
    Repo
  }

  @insert_chunk_size 1_000

  @type claims :: %{
          optional(:sub) => String.t(),
          optional(:exp) => integer(),
          optional(:name) => String.t(),
          optional(:phone) => String.t(),
          optional(:contact_id) => integer()
        }

  @doc """
  The contact holding an identity in the current organization; web identifiers are case-insensitive.
  A WhatsApp identity only counts while it still equals the contact's phone.
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
  A condition matching contacts with a web identifier containing the term, for OR-ing into a
  contact search on the first binding. It matches nothing for a `:staff` user, who may not see
  identifiers, and when there is no current user.
  """
  @spec identifier_match(String.t()) :: Ecto.Query.dynamic_expr()
  def identifier_match(term) do
    case Repo.get_current_user() do
      %{roles: roles} ->
        if :staff in roles, do: dynamic(false), else: web_identifier_match(term)

      nil ->
        dynamic(false)
    end
  end

  @doc """
  Finds, links or creates the contact for an NGO username. An identifier that already exists keeps
  its contact and ignores the claims; otherwise the `contact_id` claim, then the `phone` claim,
  name an existing contact to add the identity to, and with neither a new contact is created.
  """
  @spec resolve_or_create(:web, String.t(), claims()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def resolve_or_create(:web, identifier, claims) do
    identifier = String.downcase(identifier)

    with {:error, :not_found} <- fetch_contact(:web, identifier) do
      organization_id = Repo.get_organization_id()

      case find_contact_by_id_or_phone(organization_id, claims) do
        %Contact{} = contact -> add_web_identity(contact, identifier)
        nil -> create_web_contact(organization_id, identifier, claims)
      end
    end
  end

  @doc """
  Inserts a contact and its identity on a channel in one transaction, so neither exists without
  the other. A web contact keeps any phone it is given but gets no WhatsApp identity until that
  number messages on WhatsApp. `insert_opts` go to the contact insert (an upsert's `on_conflict`). Returns the changeset of whichever insert failed.
  """
  @spec create_contact_with_identity(map(), MessageChannel.t(), String.t() | nil, keyword()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_with_identity(attrs, channel, identifier, insert_opts \\ []) do
    Multi.new()
    |> Multi.insert(:contact, Contacts.new_contact_changeset(attrs, channel), insert_opts)
    |> Multi.insert(
      :identity,
      fn %{contact: contact} -> identity_changeset(contact, channel, identifier) end,
      identity_insert_opts(channel)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{contact: contact}} -> {:ok, contact}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Records that a contact signed in to the web with its phone, doing nothing if it already has.
  """
  @spec add_web_identity_for_phone(Contact.t()) :: :ok
  def add_web_identity_for_phone(%Contact{phone: phone}) when phone in [nil, ""], do: :ok

  def add_web_identity_for_phone(%Contact{} = contact) do
    contact
    |> identity_changeset(:web, contact.phone)
    |> Repo.insert(ignore_conflict_opts())

    :ok
  end

  @doc """
  Makes a contact's WhatsApp identity match its current phone, creating it if it has none. A row
  for that phone left on another contact whose phone has since changed is deleted first.
  """
  @spec set_whatsapp_identity(Contact.t()) :: :ok
  def set_whatsapp_identity(%Contact{phone: phone}) when phone in [nil, ""], do: :ok

  def set_whatsapp_identity(%Contact{id: contact_id, phone: phone} = contact) do
    delete_stale_whatsapp_identities(contact)

    {updated, _rows} =
      from(i in ContactIdentity,
        where: i.channel == :whatsapp and i.contact_id == ^contact_id
      )
      |> Repo.update_all(set: [identifier: phone, updated_at: DateTime.utc_now()])

    if updated == 0 do
      contact
      |> identity_changeset(:whatsapp, phone)
      |> Repo.insert(ignore_conflict_opts())
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
  Records the `(whatsapp, phone)` identity of many contacts at once, skipping those that exist,
  inserting any number of rows in batches. Every row belongs to `organization_id`.
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

  @spec web_identifier_match(String.t()) :: Ecto.Query.dynamic_expr()
  defp web_identifier_match(term) do
    pattern = "%#{String.downcase(term)}%"

    matching =
      from(i in ContactIdentity,
        where: i.channel == :web and ilike(i.identifier, ^pattern),
        select: i.contact_id
      )

    dynamic([c], c.id in subquery(matching))
  end

  @spec find_contact_by_id_or_phone(non_neg_integer(), claims()) :: Contact.t() | nil
  defp find_contact_by_id_or_phone(organization_id, claims) do
    [contact_in_organization(organization_id, claims[:contact_id]), contact_by_phone(claims)]
    |> Enum.find(&linkable?(&1, organization_id))
  end

  @spec linkable?(Contact.t() | nil, non_neg_integer()) :: boolean()
  defp linkable?(nil, _organization_id), do: false

  defp linkable?(%Contact{} = contact, organization_id),
    do:
      contact.id != Partners.organization_contact_id(organization_id) and
        not Contacts.simulator_contact?(contact.phone)

  @spec contact_in_organization(non_neg_integer(), integer() | nil) :: Contact.t() | nil
  defp contact_in_organization(_organization_id, nil), do: nil

  defp contact_in_organization(organization_id, contact_id),
    do: Repo.get_by(Contact, %{id: contact_id, organization_id: organization_id})

  @spec contact_by_phone(claims()) :: Contact.t() | nil
  defp contact_by_phone(claims) do
    case Contacts.fetch_by_identity(:whatsapp, claims[:phone]) do
      {:ok, contact} -> contact
      _not_found -> nil
    end
  end

  @spec add_web_identity(Contact.t(), String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp add_web_identity(contact, identifier) do
    with {:ok, _identity} <-
           contact
           |> identity_changeset(:web, identifier)
           |> Repo.insert(ignore_conflict_opts()) do
      fetch_username_owner(identifier, contact)
    end
  end

  @spec fetch_username_owner(String.t(), Contact.t()) :: {:ok, Contact.t()}
  defp fetch_username_owner(identifier, fallback) do
    case fetch_contact(:web, identifier) do
      {:ok, contact} -> {:ok, contact}
      {:error, :not_found} -> {:ok, fallback}
    end
  end

  @spec create_web_contact(non_neg_integer(), String.t(), claims()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp create_web_contact(organization_id, identifier, claims) do
    attrs = %{
      organization_id: organization_id,
      name: claims[:name] || identifier,
      phone: phone_not_taken(claims[:phone]),
      status: :valid,
      bsp_status: :none,
      contact_type: nil
    }

    case create_contact_with_identity(attrs, :web, identifier) do
      {:error, %Ecto.Changeset{data: %Contact{}} = changeset} ->
        add_web_identity_to_phone_owner(changeset, attrs, identifier)

      {:error, %Ecto.Changeset{data: %ContactIdentity{}} = changeset} ->
        if identifier_taken?(changeset),
          do: refetch_or_create_web_contact(organization_id, identifier, claims),
          else: {:error, changeset}

      result ->
        result
    end
  end

  @spec identifier_taken?(Ecto.Changeset.t()) :: boolean()
  defp identifier_taken?(changeset),
    do:
      Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
        opts[:constraint] == :unique
      end)

  @spec phone_not_taken(String.t() | nil) :: String.t() | nil
  defp phone_not_taken(nil), do: nil

  defp phone_not_taken(phone) do
    with false <- Contacts.simulator_contact?(phone),
         {:error, _reason} <- Contacts.fetch_by_identity(:whatsapp, phone) do
      phone
    else
      _unavailable -> nil
    end
  end

  @spec add_web_identity_to_phone_owner(Ecto.Changeset.t(), map(), String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp add_web_identity_to_phone_owner(changeset, %{phone: phone}, identifier)
       when is_binary(phone) do
    with true <- Keyword.has_key?(changeset.errors, :phone),
         {:ok, owner} <- Contacts.fetch_by_identity(:whatsapp, phone),
         true <- linkable?(owner, changeset.data.organization_id) do
      add_web_identity(owner, identifier)
    else
      _no_recovery -> {:error, changeset}
    end
  end

  defp add_web_identity_to_phone_owner(changeset, _attrs, _identifier), do: {:error, changeset}

  @spec refetch_or_create_web_contact(non_neg_integer(), String.t(), claims()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp refetch_or_create_web_contact(organization_id, identifier, claims) do
    with {:error, :not_found} <- fetch_contact(:web, identifier) do
      create_web_contact(organization_id, identifier, claims)
    end
  end

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
