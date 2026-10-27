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
  queue. A rerun is safe, and the chain ends with `ANALYZE contact_identities`.

  A chunk can race a write the application makes while it runs and leave one row a write behind.
  `find_mismatches/1` finds those rows and `fix_mismatches/1` copies them again. Check until it reports
  none, and before reading identities. A contact whose phone is another contact's WhatsApp identity is
  reported on every check and cannot be fixed by a copy.

  ## Run from IEx (`gigalixir remote_console`)

      # start the chain; options: :after_id (0), :batch_size (10_000), :pause seconds between chunks (1)
      iex> Glific.Contacts.IdentityStateBackfill.start()
      {:ok, %Oban.Job{}}

      # a second start while a link is queued or running is refused
      iex> Glific.Contacts.IdentityStateBackfill.start()
      {:error, :already_running}

      # progress: the queued link's after_id is the last contact id copied
      iex> Glific.Contacts.IdentityStateBackfill.status()
      [%{id: 12, state: "scheduled", after_id: 3_000_000, attempt: 0, scheduled_at: ~U[...]}]

      # stop: cancels the queued link and the running one will not enqueue another
      iex> Glific.Contacts.IdentityStateBackfill.stop()
      {:ok, 1}

      # resume from the last id logged or shown by status/0
      iex> Glific.Contacts.IdentityStateBackfill.start(after_id: 3_000_000)

      # count contacts whose identity is missing or differs, for all organizations or one
      iex> Glific.Contacts.IdentityStateBackfill.find_mismatches()
      %{scanned: 6_000_000, mismatched: 12, last_id: 7_123_456, sample_ids: [101, 205]}
      iex> Glific.Contacts.IdentityStateBackfill.find_mismatches(organization_id: 1)

      # copy the mismatched contacts again
      iex> Glific.Contacts.IdentityStateBackfill.fix_mismatches()
      %{scanned: 6_000_000, mismatched: 12, fixed: 12, last_id: 7_123_456}

  Every chunk is one statement with a two minute timeout; a timeout rolls that chunk back and the job
  retries it.
  """

  require Logger

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentities,
    Contacts.ContactIdentity,
    Contacts.IdentityStateWorker,
    Enums.MessageChannel,
    Repo
  }

  @default_batch_size 10_000
  @sample_size 20
  @chunk_timeout :timer.minutes(2)
  @analyze_timeout :timer.minutes(10)
  @incomplete_states ["available", "scheduled", "executing", "retryable"]

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
  The batch size a chain uses unless told otherwise.
  """
  @spec default_batch_size() :: pos_integer()
  def default_batch_size, do: @default_batch_size

  @doc """
  Starts the chain of copy jobs; takes `:after_id`, `:batch_size` and `:pause` (seconds between chunks).
  """
  @spec start(Keyword.t()) :: {:ok, Oban.Job.t()} | {:error, :already_running | any()}
  def start(opts \\ []) do
    args =
      Map.merge(
        IdentityStateWorker.default_args(),
        Map.new(Keyword.take(opts, [:after_id, :batch_size, :pause]))
      )

    case args |> IdentityStateWorker.new() |> Oban.insert() do
      {:ok, %Oban.Job{conflict?: true}} -> {:error, :already_running}
      other -> other
    end
  end

  @doc """
  The links of the chain that are queued, running or waiting to retry.
  """
  @spec status() :: [link()]
  def status do
    incomplete_links()
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
  Cancels the chain; a chunk already running finishes but enqueues no other. Returns the jobs cancelled.
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
    scan_mismatches(opts, false)
    |> Map.take([:scanned, :mismatched, :last_id, :sample_ids])
  end

  @doc """
  Copies again the contacts whose WhatsApp identity is missing or differs from their `contacts` state.
  Takes the same options as `find_mismatches/1`.
  """
  @spec fix_mismatches(Keyword.t()) :: fix_result()
  def fix_mismatches(opts \\ []) do
    scan_mismatches(opts, true)
    |> Map.take([:scanned, :mismatched, :fixed, :last_id])
  end

  @spec scan_mismatches(Keyword.t(), boolean()) :: map()
  defp scan_mismatches(opts, fix?) do
    organization_id = Keyword.get(opts, :organization_id)
    after_id = Keyword.get(opts, :after_id, 0)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    totals = %{scanned: 0, mismatched: 0, fixed: 0, last_id: after_id, sample_ids: []}

    scan_from(after_id, batch_size, organization_id, fix?, totals)
  end

  @spec scan_from(non_neg_integer(), pos_integer(), non_neg_integer() | nil, boolean(), map()) ::
          map()
  defp scan_from(after_id, batch_size, organization_id, fix?, totals) do
    case chunk_bounds(after_id, batch_size, organization_id) do
      nil ->
        totals

      {upto, scanned} ->
        ids = mismatched_contact_ids(after_id, upto, organization_id)
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

        if scanned < batch_size,
          do: totals,
          else: scan_from(upto, batch_size, organization_id, fix?, totals)
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
    |> ContactIdentities.upsert_whatsapp_state_from(now, @chunk_timeout)
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
