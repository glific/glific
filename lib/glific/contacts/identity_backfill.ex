defmodule Glific.Contacts.IdentityBackfill do
  @moduledoc """
  Copies the consent and session columns of `contacts` (opt-in, opt-out, BSP status, last inbound message)
  onto each contact's `(whatsapp, phone)` identity, and checks that the two still agree. Run it by hand;
  nothing in the application calls it. It lives under `lib/glific/contacts/` because it writes
  `ContactIdentity` rows.

  `contacts` is the source of truth, and `Glific.Contacts` also writes every change to the identity, so the
  copy is a plain overwrite: each chunk of contacts, walked by id, is one
  `insert_all` from a `contacts` query that creates a missing identity and rewrites one that differs.
  No lock outlives a chunk, a rerun is safe, and an interrupted run resumes from the last id it logged. A run
  ends with `ANALYZE contact_identities`, since the table was nearly empty when the planner last saw it.

  Contacts without a phone have no WhatsApp identity and are skipped. A copy of an identity row that belongs
  to another contact is skipped too.

  A chunk can race a write the application makes while the chunk runs, and leave one row a write behind.
  `find_mismatches/1` finds those rows and `fix_mismatches/1` copies them again. Run the check until it
  reports none, and before reading identities. A contact whose phone is another contact's WhatsApp identity is
  reported on every check and cannot be fixed by a copy.

  Every batch is one statement with a two minute timeout. A timeout rolls that batch back and raises; the
  last completed id is in the latest log line, so resume with `after_id:`.

  ## Run from IEx (`gigalixir remote_console`)

      iex> Glific.Contacts.IdentityBackfill.run()
      %{scanned: 6_000_000, inserted: 5_990_000, updated: 1_200, last_id: 7_123_456}

      # resume an interrupted run from the last id it logged
      iex> Glific.Contacts.IdentityBackfill.run(after_id: 3_000_000)

      # count contacts whose identity is missing or differs, for all organizations or one
      iex> Glific.Contacts.IdentityBackfill.find_mismatches()
      %{scanned: 6_000_000, mismatched: 12, last_id: 7_123_456, sample_ids: [101, 205]}
      iex> Glific.Contacts.IdentityBackfill.find_mismatches(organization_id: 1)

      # copy the mismatched contacts again
      iex> Glific.Contacts.IdentityBackfill.fix_mismatches()
      %{scanned: 6_000_000, mismatched: 12, fixed: 12, last_id: 7_123_456}
  """

  require Logger

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.MessageChannel,
    Repo
  }

  @default_batch_size 10_000
  @sample_size 20
  @batch_timeout :timer.minutes(2)
  @analyze_timeout :timer.minutes(10)

  @typedoc "What a copy run did, and the id to resume from."
  @type run_result :: %{
          scanned: non_neg_integer(),
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          last_id: non_neg_integer()
        }

  @typedoc "What a mismatch check found, and the id to resume from."
  @type find_result :: %{
          scanned: non_neg_integer(),
          mismatched: non_neg_integer(),
          last_id: non_neg_integer(),
          sample_ids: [non_neg_integer()]
        }

  @typedoc "What a mismatch fix copied again, and the id to resume from."
  @type fix_result :: %{
          scanned: non_neg_integer(),
          mismatched: non_neg_integer(),
          fixed: non_neg_integer(),
          last_id: non_neg_integer()
        }

  @doc """
  Copies the contacts with an id above `:after_id` (default 0), `:batch_size` (default 10,000) at a time.
  """
  @spec run(Keyword.t()) :: run_result()
  def run(opts \\ []) do
    after_id = Keyword.get(opts, :after_id, 0)
    totals = %{scanned: 0, inserted: 0, updated: 0, last_id: after_id}

    result =
      each_chunk(after_id, batch_size(opts), nil, totals, fn totals, from_id, upto, scanned ->
        copied = copy(dynamic([c], c.id > ^from_id and c.id <= ^upto))

        totals = %{
          totals
          | scanned: totals.scanned + scanned,
            inserted: totals.inserted + copied.inserted,
            updated: totals.updated + copied.updated,
            last_id: upto
        }

        Logger.info(
          "Contact identity backfill reached contact #{upto}: scanned #{totals.scanned}, " <>
            "inserted #{totals.inserted}, updated #{totals.updated}"
        )

        totals
      end)

    Repo.query!("ANALYZE contact_identities", [],
      timeout: @analyze_timeout,
      skip_organization_id: true
    )

    result
  end

  @doc """
  Counts the contacts whose WhatsApp identity is missing or differs from their `contacts` state, without
  changing anything. Takes `:organization_id`, `:after_id` and `:batch_size`.
  """
  @spec find_mismatches(Keyword.t()) :: find_result()
  def find_mismatches(opts \\ []) do
    totals = scan_mismatches(opts, false)
    Map.take(totals, [:scanned, :mismatched, :last_id, :sample_ids])
  end

  @doc """
  Copies again the contacts whose WhatsApp identity is missing or differs from their `contacts` state.
  Takes the same options as `find_mismatches/1`.
  """
  @spec fix_mismatches(Keyword.t()) :: fix_result()
  def fix_mismatches(opts \\ []) do
    totals = scan_mismatches(opts, true)
    Map.take(totals, [:scanned, :mismatched, :fixed, :last_id])
  end

  @spec scan_mismatches(Keyword.t(), boolean()) :: map()
  defp scan_mismatches(opts, fix?) do
    organization_id = Keyword.get(opts, :organization_id)
    after_id = Keyword.get(opts, :after_id, 0)
    totals = %{scanned: 0, mismatched: 0, fixed: 0, last_id: after_id, sample_ids: []}

    each_chunk(after_id, batch_size(opts), organization_id, totals, fn totals,
                                                                       from_id,
                                                                       upto,
                                                                       scanned ->
      ids = mismatched_contact_ids(from_id, upto, organization_id)
      if fix? and ids != [], do: copy(dynamic([c], c.id in ^ids))

      totals = %{
        totals
        | scanned: totals.scanned + scanned,
          mismatched: totals.mismatched + length(ids),
          fixed: totals.fixed + if(fix?, do: length(ids), else: 0),
          last_id: upto,
          sample_ids: Enum.take(totals.sample_ids ++ ids, @sample_size)
      }

      Logger.info(
        "Contact identity mismatch scan reached contact #{upto}: scanned #{totals.scanned}, " <>
          "mismatched #{totals.mismatched}, fixed #{totals.fixed}"
      )

      totals
    end)
  end

  @spec batch_size(Keyword.t()) :: pos_integer()
  defp batch_size(opts), do: Keyword.get(opts, :batch_size, @default_batch_size)

  @spec with_phone(Ecto.Queryable.t()) :: Ecto.Query.t()
  defp with_phone(query), do: where(query, [c], not is_nil(c.phone) and c.phone != "")

  @spec in_organization(non_neg_integer() | nil) :: Ecto.Query.dynamic_expr()
  defp in_organization(nil), do: dynamic(true)
  defp in_organization(organization_id), do: dynamic([c], c.organization_id == ^organization_id)

  @spec copy(Ecto.Query.dynamic_expr()) :: %{
          inserted: non_neg_integer(),
          updated: non_neg_integer()
        }
  defp copy(condition) do
    now = DateTime.utc_now()

    source =
      Contact
      |> with_phone()
      |> where(^condition)
      |> select([c], %{
        contact_id: c.id,
        organization_id: c.organization_id,
        channel: type(^:whatsapp, MessageChannel),
        identifier: c.phone,
        optin_time: c.optin_time,
        optin_status: coalesce(c.optin_status, false),
        optin_method: c.optin_method,
        optout_time: c.optout_time,
        optout_method: c.optout_method,
        bsp_status: c.bsp_status,
        last_message_at: c.last_message_at,
        inserted_at: type(^now, :utc_datetime_usec),
        updated_at: type(^now, :utc_datetime_usec)
      })

    {_count, rows} =
      Repo.insert_all(
        ContactIdentity,
        source,
        [
          on_conflict: overwrite_changed_state(now),
          conflict_target: [:organization_id, :channel, :identifier],
          returning: [:inserted_at]
        ] ++ [timeout: @batch_timeout, skip_organization_id: true]
      )

    inserted = Enum.count(rows, &(&1.inserted_at == now))
    %{inserted: inserted, updated: length(rows) - inserted}
  end

  @spec overwrite_changed_state(DateTime.t()) :: Ecto.Query.t()
  defp overwrite_changed_state(now) do
    from(i in ContactIdentity,
      where: i.contact_id == fragment("EXCLUDED.contact_id"),
      where:
        fragment(
          "(?, ?, ?, ?, ?, ?, ?) IS DISTINCT FROM (EXCLUDED.optin_time, EXCLUDED.optin_status, EXCLUDED.optin_method, EXCLUDED.optout_time, EXCLUDED.optout_method, EXCLUDED.bsp_status, EXCLUDED.last_message_at)",
          i.optin_time,
          i.optin_status,
          i.optin_method,
          i.optout_time,
          i.optout_method,
          i.bsp_status,
          i.last_message_at
        ),
      update: [
        set: [
          optin_time: fragment("EXCLUDED.optin_time"),
          optin_status: fragment("EXCLUDED.optin_status"),
          optin_method: fragment("EXCLUDED.optin_method"),
          optout_time: fragment("EXCLUDED.optout_time"),
          optout_method: fragment("EXCLUDED.optout_method"),
          bsp_status: fragment("EXCLUDED.bsp_status"),
          last_message_at: fragment("EXCLUDED.last_message_at"),
          updated_at: ^now
        ]
      ]
    )
  end

  @spec mismatched_contact_ids(non_neg_integer(), non_neg_integer(), non_neg_integer() | nil) ::
          [non_neg_integer()]
  defp mismatched_contact_ids(after_id, upto, organization_id) do
    Contact
    |> with_phone()
    |> join(:left, [c], i in ContactIdentity,
      on:
        i.organization_id == c.organization_id and i.channel == :whatsapp and
          i.identifier == c.phone and i.contact_id == c.id
    )
    |> where([c], c.id > ^after_id and c.id <= ^upto)
    |> where(^in_organization(organization_id))
    |> where(
      [c, i],
      is_nil(i.id) or
        fragment(
          "(?, ?, ?, ?, ?, ?, ?) IS DISTINCT FROM (?, COALESCE(?, false), ?, ?, ?, ?, ?)",
          i.optin_time,
          i.optin_status,
          i.optin_method,
          i.optout_time,
          i.optout_method,
          i.bsp_status,
          i.last_message_at,
          c.optin_time,
          c.optin_status,
          c.optin_method,
          c.optout_time,
          c.optout_method,
          c.bsp_status,
          c.last_message_at
        )
    )
    |> order_by([c], c.id)
    |> select([c], c.id)
    |> Repo.all(timeout: @batch_timeout, skip_organization_id: true)
  end

  @spec each_chunk(
          non_neg_integer(),
          pos_integer(),
          non_neg_integer() | nil,
          map(),
          (map(), non_neg_integer(), non_neg_integer(), non_neg_integer() -> map())
        ) :: map()
  defp each_chunk(after_id, batch_size, organization_id, totals, fun) do
    case chunk_upper_bound(after_id, batch_size, organization_id) do
      nil ->
        totals

      {upto, scanned} ->
        totals = fun.(totals, after_id, upto, scanned)

        if scanned < batch_size,
          do: totals,
          else: each_chunk(upto, batch_size, organization_id, totals, fun)
    end
  end

  @spec chunk_upper_bound(non_neg_integer(), pos_integer(), non_neg_integer() | nil) ::
          {non_neg_integer(), non_neg_integer()} | nil
  defp chunk_upper_bound(after_id, batch_size, organization_id) do
    ids =
      Contact
      |> with_phone()
      |> where([c], c.id > ^after_id)
      |> where(^in_organization(organization_id))
      |> order_by([c], c.id)
      |> limit(^batch_size)
      |> select([c], c.id)

    case Repo.one(from(c in subquery(ids), select: {max(c.id), count()}),
           timeout: @batch_timeout,
           skip_organization_id: true
         ) do
      {nil, _scanned} -> nil
      bounds -> bounds
    end
  end
end
