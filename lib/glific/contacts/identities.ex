defmodule Glific.Contacts.Identities do
  @moduledoc """
  Reads and writes `Glific.Contacts.ContactIdentity` rows: the logins a contact can be reached or
  recognised by.

  A `:whatsapp` identity mirrors `contacts.phone` and is kept in step with it by the contact write
  paths. A `:web` identity is an opaque username issued by an NGO's own system, and is never a
  phone: a contact signing in with a one-time code is found by `contacts.phone`, and recording it
  here would let an NGO username equal to that phone number reach the same conversation.
  `resolve_or_create/3` is how a first login or a provisioning call turns a username into a contact.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.MessageChannel,
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
  The contact holding an identity in the current organization.
  """
  @spec fetch_contact(MessageChannel.t(), String.t()) ::
          {:ok, Contact.t()} | {:error, :not_found}
  def fetch_contact(channel, identifier) do
    query =
      from(i in ContactIdentity,
        join: c in assoc(i, :contact),
        where: i.channel == ^channel and i.identifier == ^identifier,
        select: c
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  @doc """
  Finds, links or creates the contact for an NGO username. An identifier that already exists keeps
  its contact and ignores the claims; otherwise the `contact_id` claim, then the `phone` claim,
  name an existing contact to link to, and with neither a new contact is created.
  """
  @spec resolve_or_create(:web, String.t(), claims()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def resolve_or_create(:web, identifier, claims) do
    with {:error, :not_found} <- fetch_contact(:web, identifier) do
      organization_id = Repo.get_organization_id()

      case link_target(organization_id, claims) do
        %Contact{} = target -> link(target, identifier)
        nil -> create_with_identity(organization_id, identifier, claims)
      end
    end
  end

  @doc """
  Records the `(whatsapp, phone)` identity of a contact, doing nothing if it already exists.
  """
  @spec ensure_whatsapp_identity(Contact.t()) :: :ok
  def ensure_whatsapp_identity(%Contact{phone: phone}) when phone in [nil, ""], do: :ok

  def ensure_whatsapp_identity(%Contact{} = contact) do
    contact
    |> identity_changeset(:whatsapp, contact.phone)
    |> Repo.insert(on_conflict: :nothing, conflict_target: conflict_target())

    :ok
  end

  @doc """
  Points a contact's WhatsApp identity at its current phone, creating it if the contact has none.
  """
  @spec sync_whatsapp_identity(Contact.t()) :: :ok
  def sync_whatsapp_identity(%Contact{phone: phone}) when phone in [nil, ""], do: :ok

  def sync_whatsapp_identity(%Contact{id: contact_id, phone: phone} = contact) do
    {updated, _rows} =
      from(i in ContactIdentity,
        where: i.channel == :whatsapp and i.contact_id == ^contact_id
      )
      |> Repo.update_all(set: [identifier: phone, updated_at: DateTime.utc_now()])

    if updated == 0, do: ensure_whatsapp_identity(contact), else: :ok
  end

  @doc """
  Records the `(whatsapp, phone)` identity of many contacts at once, skipping those that exist,
  inserting any number of rows in batches. Pass `organization_id` when every row is from one
  organization (CSV import, whose rows don't carry it); leave it `nil` for rows spanning
  organizations (the backfill), and each row's own `organization_id` is used.
  """
  @spec insert_whatsapp_identities([map()], non_neg_integer() | nil) :: :ok
  def insert_whatsapp_identities(rows, organization_id \\ nil) do
    now = DateTime.utc_now()

    rows
    |> Stream.filter(&(is_binary(&1.phone) and &1.phone != ""))
    |> Stream.map(fn row ->
      %{
        contact_id: row.id,
        organization_id: organization_id || row.organization_id,
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

  @spec link_target(non_neg_integer(), claims()) :: Contact.t() | nil
  defp link_target(organization_id, claims),
    do: contact_in_organization(organization_id, claims[:contact_id]) || contact_by_phone(claims)

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

  @spec link(Contact.t(), String.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp link(target, identifier) do
    with {:ok, _identity} <-
           target
           |> identity_changeset(:web, identifier)
           |> Repo.insert(on_conflict: :nothing, conflict_target: conflict_target()) do
      fetch_existing(identifier, target)
    end
  end

  @spec fetch_existing(String.t(), Contact.t()) :: {:ok, Contact.t()}
  defp fetch_existing(identifier, fallback) do
    case fetch_contact(:web, identifier) do
      {:ok, contact} -> {:ok, contact}
      {:error, :not_found} -> {:ok, fallback}
    end
  end

  @spec create_with_identity(non_neg_integer(), String.t(), claims()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp create_with_identity(organization_id, identifier, claims) do
    attrs = %{
      organization_id: organization_id,
      name: claims[:name] || identifier,
      phone: unclaimed_phone(claims[:phone]),
      status: :valid,
      bsp_status: :none,
      contact_type: nil
    }

    Multi.new()
    |> Multi.insert(:contact, Contacts.new_contact_changeset(attrs, :web))
    |> Multi.insert(:identity, fn %{contact: contact} ->
      identity_changeset(contact, :web, identifier)
    end)
    |> Multi.run(:whatsapp_identity, fn _repo, %{contact: contact} ->
      {:ok, ensure_whatsapp_identity(contact)}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{contact: contact}} ->
        {:ok, contact}

      {:error, :contact, changeset, _changes} ->
        recover_phone_conflict(changeset, attrs, identifier)

      {:error, :identity, _changeset, _changes} ->
        reread(organization_id, identifier, claims)
    end
  end

  @spec unclaimed_phone(String.t() | nil) :: String.t() | nil
  defp unclaimed_phone(nil), do: nil

  defp unclaimed_phone(phone) do
    case Contacts.fetch_by_identity(:whatsapp, phone) do
      {:ok, _contact} -> nil
      {:error, _reason} -> phone
    end
  end

  @spec recover_phone_conflict(Ecto.Changeset.t(), map(), String.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp recover_phone_conflict(changeset, %{phone: phone}, identifier) when is_binary(phone) do
    with true <- Keyword.has_key?(changeset.errors, :phone),
         {:ok, target} <- Contacts.fetch_by_identity(:whatsapp, phone) do
      link(target, identifier)
    else
      _no_recovery -> {:error, changeset}
    end
  end

  defp recover_phone_conflict(changeset, _attrs, _identifier), do: {:error, changeset}

  @spec reread(non_neg_integer(), String.t(), claims()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  defp reread(organization_id, identifier, claims) do
    with {:error, :not_found} <- fetch_contact(:web, identifier) do
      create_with_identity(organization_id, identifier, claims)
    end
  end

  @spec identity_changeset(Contact.t(), MessageChannel.t(), String.t()) :: Ecto.Changeset.t()
  defp identity_changeset(contact, channel, identifier) do
    ContactIdentity.changeset(%ContactIdentity{}, %{
      contact_id: contact.id,
      organization_id: contact.organization_id,
      channel: channel,
      identifier: identifier
    })
  end

  @spec conflict_target() :: [atom()]
  defp conflict_target, do: [:organization_id, :channel, :identifier]
end
