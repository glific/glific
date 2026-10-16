defmodule Glific.Contacts.IdentityBackfill do
  @moduledoc """
  One-off backfill of the `(whatsapp, contacts.phone)` identity for contacts created before
  identities existed. It lives under `lib/glific/contacts/` because it writes `ContactIdentity`
  rows; nothing in the application calls it.

  Every contact with a non-empty phone and no WhatsApp identity is backfilled.

  Contacts are read in id order, `batch_size` at a time, across all organizations, and each batch
  is inserted in its own statement, so no lock outlives a batch. Rows that already exist, or whose
  phone is a WhatsApp identity of another contact, are skipped by the unique
  `(organization_id, channel, identifier)` index, so a rerun is safe.

  ## Run from IEx (`gigalixir remote_console`)

      iex> Glific.Contacts.IdentityBackfill.run()
      %{scanned: 6_000_000, inserted: 5_990_000, last_id: 7_123_456}

      # resume after an interrupted run, from the last id it logged
      iex> Glific.Contacts.IdentityBackfill.run(after_id: 3_000_000)
  """

  import Ecto.Query

  require Logger

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Repo
  }

  @default_batch_size 1_000

  @typedoc "What a run did, and the id to resume from."
  @type result :: %{
          scanned: non_neg_integer(),
          inserted: non_neg_integer(),
          last_id: non_neg_integer()
        }

  @doc """
  Backfills every eligible contact with an id above `:after_id` (default 0), `:batch_size` at a time.
  """
  @spec run(Keyword.t()) :: result()
  def run(opts \\ []) do
    after_id = Keyword.get(opts, :after_id, 0)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    run_batches(after_id, batch_size, %{scanned: 0, inserted: 0, last_id: after_id})
  end

  @spec run_batches(non_neg_integer(), pos_integer(), result()) :: result()
  defp run_batches(after_id, batch_size, totals) do
    contacts = fetch_batch(after_id, batch_size)

    case List.last(contacts) do
      nil ->
        totals

      %{id: last_id} ->
        inserted = insert_whatsapp_identities(contacts)
        Logger.info("Contact identity backfill reached contact #{last_id}")

        totals = %{
          scanned: totals.scanned + length(contacts),
          inserted: totals.inserted + inserted,
          last_id: last_id
        }

        if length(contacts) < batch_size,
          do: totals,
          else: run_batches(last_id, batch_size, totals)
    end
  end

  @spec fetch_batch(non_neg_integer(), pos_integer()) :: [map()]
  defp fetch_batch(after_id, batch_size) do
    from(c in Contact, as: :contact)
    |> where([c], c.id > ^after_id and not is_nil(c.phone) and c.phone != "")
    |> where([c], not exists(whatsapp_identities()))
    |> order_by([c], asc: c.id)
    |> limit(^batch_size)
    |> select([c], %{id: c.id, organization_id: c.organization_id, phone: c.phone})
    |> Repo.all(skip_organization_id: true)
  end

  @spec whatsapp_identities() :: Ecto.Query.t()
  defp whatsapp_identities do
    from(i in ContactIdentity,
      where: i.contact_id == parent_as(:contact).id and i.channel == :whatsapp
    )
  end

  @spec insert_whatsapp_identities([map()]) :: non_neg_integer()
  defp insert_whatsapp_identities(contacts) do
    now = DateTime.utc_now()

    rows =
      Enum.map(contacts, fn contact ->
        %{
          contact_id: contact.id,
          organization_id: contact.organization_id,
          channel: :whatsapp,
          identifier: contact.phone,
          inserted_at: now,
          updated_at: now
        }
      end)

    {inserted, _rows} =
      Repo.insert_all(ContactIdentity, rows,
        on_conflict: :nothing,
        conflict_target: [:organization_id, :channel, :identifier],
        skip_organization_id: true
      )

    inserted
  end
end
