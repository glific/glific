defmodule Glific.Contacts.IdentityStateBackfill do
  @moduledoc """
  Copies the consent and session columns of `contacts` (opt-in, opt-out, BSP status, last inbound message)
  onto each contact's `(whatsapp, phone)` identity, and checks that the two still agree. It lives under
  `lib/glific/contacts/` because it writes `ContactIdentity` rows.

  `contacts` is the source of truth, and `Glific.Contacts` also writes every change to an existing
  identity, so the copy is a plain overwrite. Each chunk of contacts, walked by id, is one `insert_all`
  from a `contacts` query that creates a missing identity and rewrites one of the same contact that
  differs. A row another contact holds is left alone. Contacts without a phone have no WhatsApp identity
  and are skipped.

  The copy runs as a chain of `Glific.Contacts.IdentityStateWorker` jobs, one chunk each, on the `:purge`
  queue, so a chain outlives a crash or a deploy: Oban retries the chunk and carries on. A rerun is safe,
  and the chain ends with `ANALYZE contact_identities`.

  A chunk can race a write the application makes while it runs and leave one row a write behind.
  `find_mismatches/1` finds those rows and `fix_mismatches/1` copies them again. Check until it reports
  none, and before reading identities. A contact whose phone is another contact's WhatsApp identity is
  reported on every check and cannot be fixed by a copy. `unfixable` can also count a contact an app write
  fixed during the scan; only the ones reported again on the next check are real.

  ## Run from IEx (`gigalixir remote_console`)

      # start the chain; options: :after_id (0), :batch_size (5_000), :pause whole seconds between chunks (1)
      iex> Glific.Contacts.IdentityStateBackfill.start()
      {:ok, %Oban.Job{}}

      # a second start while any link is queued, running or retrying is refused
      iex> Glific.Contacts.IdentityStateBackfill.start()
      {:error, :already_running}

      # progress: the queued link's after_id is the last contact id copied
      iex> Glific.Contacts.IdentityStateBackfill.status()
      [%{id: 12, state: "scheduled", after_id: 3_000_000, attempt: 0, scheduled_at: ~U[...]}]

      # stop: cancels the queued link and kills a running one, whose chunk rolls back
      iex> Glific.Contacts.IdentityStateBackfill.stop()
      {:ok, 1}

      # resume from the last id logged or shown by status/0
      iex> Glific.Contacts.IdentityStateBackfill.start(after_id: 3_000_000)

      # count contacts whose identity is missing or differs, for all organizations or one
      iex> Glific.Contacts.IdentityStateBackfill.find_mismatches()
      %{scanned: 6_000_000, mismatched: 12, last_id: 7_123_456, sample_ids: [101, 205]}
      iex> Glific.Contacts.IdentityStateBackfill.find_mismatches(organization_id: 1)

      # an organization filter can be slow on a large table; scan a big one in segments
      iex> Glific.Contacts.IdentityStateBackfill.find_mismatches(organization_id: 1, after_id: 3_000_000)

      # copy the mismatched contacts again
      iex> Glific.Contacts.IdentityStateBackfill.fix_mismatches()
      %{scanned: 6_000_000, mismatched: 12, fixed: 11, unfixable: 1, last_id: 7_123_456}

  Every chunk is one statement with a two minute timeout; a timeout rolls that chunk back and the job
  retries it. A chunk that fails every attempt ends the chain and is logged as an error with the id to
  resume from; `status/0` shows it as "discarded" only until Oban prunes it, minutes later. A node that
  dies during a last attempt discards the job with no log, so an empty `status/0` never means done: the
  chain is done only when the log says "Finished copying contact state".

  ## While it runs, and after

    * Run it off-peak, and not on Friday from 21:00 to 22:00 UTC, when the weekly purge uses the same
      `:purge` queue. A chunk locks the identity rows it writes, so inbound messages for contacts in
      that chunk wait for it. Start with the default batch, check the first chunk times in AppSignal,
      and only then raise `:batch_size`.
    * Watch replication lag and WAL volume. Every chunk writes its rows and four index entries, so a
      few million contacts write a few GB of WAL. Raise `:pause` or lower `:batch_size` to slow it down.
    * After the chain, run `VACUUM (ANALYZE) contact_identities` from `psql`; it cannot run in a transaction.
    * Before deleting this module, run `stop/0`, so no queued link is left for a worker that no longer exists.
  """

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Contacts.IdentityStateWorker,
    Enums.MessageChannel,
    Repo
  }

  @default_batch_size 5_000
  @default_pause 1
  @sample_size 20
  @chunk_timeout :timer.minutes(2)
  @analyze_timeout :timer.minutes(10)
  @incomplete_states ["available", "scheduled", "executing", "retryable"]
  @status_states @incomplete_states ++ ["discarded"]

  @typedoc "What one chunk copied, and the id to continue from."
  @type chunk_result :: %{
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
          unfixable: non_neg_integer(),
          last_id: non_neg_integer()
        }

  @typedoc "A link of the chain that has not finished."
  @type link :: %{
          id: non_neg_integer(),
          state: String.t(),
          after_id: non_neg_integer(),
          attempt: non_neg_integer(),
          scheduled_at: DateTime.t()
        }

  @doc """
  Starts the chain of copy jobs; takes `:after_id`, `:batch_size` and `:pause` (whole seconds between chunks).
  """
  @spec start(Keyword.t()) ::
          {:ok, Oban.Job.t()}
          | {:error, :already_running | {:invalid_option, atom()} | any()}
  def start(opts \\ []) do
    args =
      Map.merge(
        %{after_id: 0, batch_size: @default_batch_size, pause: @default_pause},
        Map.new(Keyword.take(opts, [:after_id, :batch_size, :pause]))
      )

    cond do
      invalid = invalid_option(args) -> {:error, {:invalid_option, invalid}}
      another_link?(nil) -> {:error, :already_running}
      true -> insert_first_link(args)
    end
  end

  # A batch_size of 0 scans nothing yet never ends the chain, and a fractional pause cannot be scheduled.
  @spec invalid_option(map()) :: atom() | nil
  defp invalid_option(%{after_id: after_id}) when not is_integer(after_id) or after_id < 0,
    do: :after_id

  defp invalid_option(%{batch_size: size}) when not is_integer(size) or size < 1, do: :batch_size
  defp invalid_option(%{pause: pause}) when not is_integer(pause) or pause < 0, do: :pause
  defp invalid_option(_args), do: nil

  # Oban's unique check alone is not enough: the links after the first are inserted without a
  # uniqueness key, so it would let a second chain start once the first link has handed off.
  @spec insert_first_link(map()) :: {:ok, Oban.Job.t()} | {:error, :already_running | any()}
  defp insert_first_link(args) do
    case args |> IdentityStateWorker.new() |> Oban.insert() do
      {:ok, %Oban.Job{conflict?: true}} -> {:error, :already_running}
      other -> other
    end
  end

  @doc """
  Whether a link of the chain other than the job `job_id` is queued, running or waiting to retry.
  """
  @spec another_link?(non_neg_integer() | nil) :: boolean()
  def another_link?(job_id) do
    incomplete_links()
    |> then(fn query -> if job_id, do: where(query, [j], j.id != ^job_id), else: query end)
    |> then(&Oban.Repo.exists?(Oban.config(), &1))
  end

  @doc """
  The links of the chain that are queued, running or waiting to retry, and any that gave up.
  """
  @spec status() :: [link()]
  def status do
    worker = Oban.Worker.to_string(IdentityStateWorker)

    from(j in Oban.Job, where: j.worker == ^worker and j.state in ^@status_states)
    |> select([j], %{
      id: j.id,
      state: j.state,
      after_id: fragment("?->>'after_id'", j.args),
      attempt: j.attempt,
      scheduled_at: j.scheduled_at
    })
    |> then(&Oban.Repo.all(Oban.config(), &1))
    |> Enum.map(&Map.update!(&1, :after_id, fn after_id -> String.to_integer(after_id) end))
  end

  @doc """
  Cancels the chain; Oban kills a running chunk, which rolls back and is copied again on resume.
  """
  @spec stop() :: {:ok, non_neg_integer()}
  def stop, do: Oban.cancel_all_jobs(incomplete_links())

  @spec incomplete_links() :: Ecto.Query.t()
  defp incomplete_links do
    worker = Oban.Worker.to_string(IdentityStateWorker)
    from(j in Oban.Job, where: j.worker == ^worker and j.state in ^@incomplete_states)
  end

  @doc """
  Copies the next `batch_size` contacts with an id above `after_id` onto their WhatsApp identities.
  """
  @spec copy_chunk(non_neg_integer(), pos_integer()) :: chunk_result()
  def copy_chunk(after_id, batch_size) do
    case chunk_bounds(after_id, batch_size, nil) do
      nil ->
        %{scanned: 0, inserted: 0, updated: 0, last_id: after_id}

      {upto, scanned} ->
        copied = copy(dynamic([c], c.id > ^after_id and c.id <= ^upto))
        Map.merge(copied, %{scanned: scanned, last_id: upto})
    end
  end

  @doc """
  Refreshes the planner statistics of `contact_identities`, which was nearly empty when it last looked.
  """
  @spec analyze() :: :ok
  def analyze do
    Repo.query!("ANALYZE contact_identities", [],
      timeout: @analyze_timeout,
      skip_organization_id: true
    )

    :ok
  end

  @doc """
  Counts the contacts whose WhatsApp identity is missing or differs from their `contacts` state, without
  changing anything. Takes `:organization_id`, `:after_id` and `:batch_size`.
  """
  @spec find_mismatches(Keyword.t()) :: find_result()
  def find_mismatches(opts \\ []) do
    opts
    |> scan_mismatches(fn _ids -> 0 end)
    |> Map.delete(:fixed)
  end

  @doc """
  Copies again the contacts whose WhatsApp identity is missing or differs; one held by another contact is
  counted as unfixable. Takes the same options as `find_mismatches/1`.
  """
  @spec fix_mismatches(Keyword.t()) :: fix_result()
  def fix_mismatches(opts \\ []) do
    %{mismatched: mismatched, fixed: fixed} = totals = scan_mismatches(opts, &copy_again/1)

    totals
    |> Map.delete(:sample_ids)
    |> Map.put(:unfixable, mismatched - fixed)
  end

  @spec copy_again([non_neg_integer()]) :: non_neg_integer()
  defp copy_again([]), do: 0

  defp copy_again(ids) do
    %{inserted: inserted, updated: updated} = copy(dynamic([c], c.id in ^ids))
    inserted + updated
  end

  @spec scan_mismatches(Keyword.t(), ([non_neg_integer()] -> non_neg_integer())) :: map()
  defp scan_mismatches(opts, on_mismatches) do
    after_id = Keyword.get(opts, :after_id, 0)

    scan_from(after_id, %{
      organization_id: Keyword.get(opts, :organization_id),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      on_mismatches: on_mismatches,
      totals: %{scanned: 0, mismatched: 0, fixed: 0, last_id: after_id, sample_ids: []}
    })
  end

  @spec scan_from(non_neg_integer(), map()) :: map()
  defp scan_from(after_id, %{totals: totals} = scan) do
    case chunk_bounds(after_id, scan.batch_size, scan.organization_id) do
      nil ->
        totals

      {upto, scanned} ->
        ids = mismatched_contact_ids(after_id, upto, scan.organization_id)

        totals = %{
          totals
          | scanned: totals.scanned + scanned,
            mismatched: totals.mismatched + length(ids),
            fixed: totals.fixed + scan.on_mismatches.(ids),
            last_id: upto,
            sample_ids: Enum.take(totals.sample_ids ++ ids, @sample_size)
        }

        Appsignal.Logger.info(
          "contact_identity_state",
          "Mismatch scan reached contact #{upto}: scanned #{totals.scanned}, " <>
            "mismatched #{totals.mismatched}, fixed #{totals.fixed}"
        )

        if scanned < scan.batch_size,
          do: totals,
          else: scan_from(upto, %{scan | totals: totals})
    end
  end

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

    # Deliberately across organizations: each contact's identity takes its own organization_id.
    Contact
    |> with_phone()
    |> where(^condition)
    |> order_by([c], c.id)
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
      bsp_status: coalesce(c.bsp_status, type(^:none, Glific.Enums.ContactProviderStatus)),
      last_message_at: c.last_message_at,
      inserted_at: type(^now, :utc_datetime_usec),
      updated_at: type(^now, :utc_datetime_usec)
    })
    |> then(
      &Repo.insert_all(ContactIdentity, &1,
        on_conflict: replace_differing_state_of_same_contact(),
        conflict_target: [:organization_id, :channel, :identifier],
        returning: [:inserted_at],
        timeout: @chunk_timeout,
        skip_organization_id: true
      )
    )
    |> then(fn {count, rows} ->
      inserted = Enum.count(rows, &(&1.inserted_at == now))
      %{inserted: inserted, updated: count - inserted}
    end)
  end

  # A copy of ContactIdentities' conflict rule, so this module deletes on its own; keep the two in step.
  @spec replace_differing_state_of_same_contact() :: Ecto.Query.t()
  defp replace_differing_state_of_same_contact do
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
          updated_at: fragment("EXCLUDED.updated_at")
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
          "(?, ?, ?, ?, ?, ?, ?) IS DISTINCT FROM (?, COALESCE(?, false), ?, ?, ?, COALESCE(?, 'none'), ?)",
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
    |> Repo.all(timeout: @chunk_timeout, skip_organization_id: true)
  end

  @spec chunk_bounds(non_neg_integer(), pos_integer(), non_neg_integer() | nil) ::
          {non_neg_integer(), non_neg_integer()} | nil
  defp chunk_bounds(after_id, batch_size, organization_id) do
    ids =
      Contact
      |> with_phone()
      |> where([c], c.id > ^after_id)
      |> where(^in_organization(organization_id))
      |> order_by([c], c.id)
      |> limit(^batch_size)
      |> select([c], c.id)

    case Repo.one(from(c in subquery(ids), select: {max(c.id), count()}),
           timeout: @chunk_timeout,
           skip_organization_id: true
         ) do
      {nil, _scanned} -> nil
      bounds -> bounds
    end
  end
end
