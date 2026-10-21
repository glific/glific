defmodule Glific.Contacts.IdentityBackfill do
  @moduledoc """
  One-off copy of the old `contacts` consent and session columns (opt-in, opt-out, BSP status, last inbound
  message) onto each contact's `(whatsapp, phone)` identity, creating the identity where it is missing. It
  lives under `lib/glific/contacts/` because it writes `ContactIdentity` rows; nothing in the application
  calls it.

  The application reads those fields from identities only, so a contact without an identity row reads as not
  opted in until this reaches it. Run it immediately after the deploy, and hold organization broadcasts and
  scheduled campaigns until it has finished: a broadcast in the window would message contacts whose opt-out
  has not been copied yet.

  It is set-based: contacts are walked in id ranges of `batch_size` with partial phones skipped, and each range
  is a single `INSERT ... SELECT ... ON CONFLICT` statement, so no lock outlives a batch and a rerun is safe.

  It runs two passes. The `:priority` pass copies only the contacts that have opted out or sent a message in
  the last 30 days, the ones a broadcast or an import could wrongly reach or re-opt-in, which are few. The
  `:full` pass then walks every contact; the merge below leaves the rows of the first pass as they are. A
  run ends with `ANALYZE contact_identities`, since the table was empty when the planner last saw it.

  ## Rows the running application wrote first

  Between the deploy and the backfill the application may already have written an identity row (an opt-in,
  an inbound message, a new contact). An existing row is never overwritten with the older contact values:

    * consent (opt-in and opt-out fields) is copied only while the row records none; once it holds any,
      the row is newer than the contact and is left alone, so an opt-out is never undone by a stale opt-in;
    * `bsp_status` is copied only while the row is still `none`, and a `session` status over a copied opt-in
      becomes `session_and_hsm`;
    * `last_message_at` keeps the later of the two times.

  A row that belongs to another contact (a phone that moved) is skipped.

  ## Run from IEx (`gigalixir remote_console`)

      iex> Glific.Contacts.IdentityBackfill.run()
      %{scanned: 6_000_000, inserted: 5_990_000, updated: 1_200, last_id: 7_123_456}

      # resume an interrupted run from the last id it logged, in the pass that was running
      iex> Glific.Contacts.IdentityBackfill.run(phase: :priority, after_id: 3_000_000)
      iex> Glific.Contacts.IdentityBackfill.run(phase: :full, after_id: 3_000_000)

  `:phase` is `:all` (both passes, the default), `:priority` or `:full`. `:after_id` belongs to one pass, so it
  needs an explicit `:phase`. Resume an interrupted `:priority` pass with `phase: :priority` and then run
  `phase: :full` from the start; resume an interrupted `:full` pass with `phase: :full`.
  """

  require Logger

  alias Glific.Repo

  @default_batch_size 10_000

  @typedoc "What a run did, and the pass and id to resume from."
  @type result :: %{
          phase: :priority | :full,
          scanned: non_neg_integer(),
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          last_id: non_neg_integer()
        }

  @consent_unrecorded """
  (i.optin_time IS NULL AND i.optout_time IS NULL AND i.optin_method IS NULL
   AND i.optout_method IS NULL AND NOT i.optin_status)
  """

  @priority_contacts "(c.optout_time IS NOT NULL OR c.last_message_at > now() - interval '30 days')"

  @merged_bsp_status """
  CASE
    WHEN NOT #{@consent_unrecorded} THEN i.bsp_status
    WHEN i.bsp_status = 'none' THEN EXCLUDED.bsp_status
    WHEN i.bsp_status = 'session' AND EXCLUDED.optin_time IS NOT NULL THEN 'session_and_hsm'
    ELSE i.bsp_status
  END
  """

  @copy_select """
  INSERT INTO contact_identities AS i
    (contact_id, organization_id, channel, identifier, optin_time, optin_status, optin_method,
     optout_time, optout_method, bsp_status, last_message_at, inserted_at, updated_at)
  SELECT c.id, c.organization_id, 'whatsapp', c.phone, c.optin_time, COALESCE(c.optin_status, false),
         c.optin_method, c.optout_time, c.optout_method, COALESCE(c.bsp_status, 'none'),
         c.last_message_at, now(), now()
  FROM contacts c
  WHERE c.id > $1 AND c.id <= $2 AND c.phone IS NOT NULL AND c.phone <> ''
  """

  @copy_upsert """
  ON CONFLICT (organization_id, channel, identifier) DO UPDATE SET
    optin_time = CASE WHEN #{@consent_unrecorded} THEN EXCLUDED.optin_time ELSE i.optin_time END,
    optin_status = CASE WHEN #{@consent_unrecorded} THEN EXCLUDED.optin_status ELSE i.optin_status END,
    optin_method = CASE WHEN #{@consent_unrecorded} THEN EXCLUDED.optin_method ELSE i.optin_method END,
    optout_time = CASE WHEN #{@consent_unrecorded} THEN EXCLUDED.optout_time ELSE i.optout_time END,
    optout_method = CASE WHEN #{@consent_unrecorded} THEN EXCLUDED.optout_method ELSE i.optout_method END,
    bsp_status = #{@merged_bsp_status},
    last_message_at = GREATEST(i.last_message_at, EXCLUDED.last_message_at),
    updated_at = now()
  WHERE i.contact_id = EXCLUDED.contact_id
    AND (
      (#{@consent_unrecorded} AND (EXCLUDED.optin_time IS NOT NULL OR EXCLUDED.optout_time IS NOT NULL
        OR EXCLUDED.optin_status OR EXCLUDED.optin_method IS NOT NULL
        OR EXCLUDED.optout_method IS NOT NULL))
      OR (i.bsp_status, i.last_message_at) IS DISTINCT FROM
         (#{@merged_bsp_status}, GREATEST(i.last_message_at, EXCLUDED.last_message_at))
    )
  RETURNING (xmax = 0) AS inserted
  """

  @copy_sql %{
    priority: "#{@copy_select} AND #{@priority_contacts}\n#{@copy_upsert}",
    full: "#{@copy_select}#{@copy_upsert}"
  }

  @batch_filter %{priority: " AND #{@priority_contacts}", full: ""}

  @doc """
  The SQL condition, over an identity aliased `i`, that the row records no consent: nothing but defaults.
  """
  @spec consent_unrecorded_sql() :: String.t()
  def consent_unrecorded_sql, do: @consent_unrecorded

  @doc """
  Copies the contacts with an id above `:after_id` (default 0), `:batch_size` at a time, in the passes `:phase`
  names (`:all` by default, which cannot take an `:after_id`).
  """
  @spec run(Keyword.t()) :: result()
  def run(opts \\ []) do
    after_id = Keyword.get(opts, :after_id, 0)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    result =
      case {Keyword.get(opts, :phase, :all), after_id} do
        {:all, 0} ->
          sum_results(copy_pass(:priority, 0, batch_size), copy_pass(:full, 0, batch_size))

        {:all, _after_id} ->
          raise ArgumentError, "an :after_id belongs to one pass, so it needs a :phase"

        {phase, _after_id} ->
          copy_pass(phase, after_id, batch_size)
      end

    Repo.query!("ANALYZE contact_identities", [], timeout: :infinity, skip_organization_id: true)

    result
  end

  @spec copy_pass(:priority | :full, non_neg_integer(), pos_integer()) :: result()
  defp copy_pass(phase, after_id, batch_size) do
    copy_batches(phase, after_id, batch_size, %{
      phase: phase,
      scanned: 0,
      inserted: 0,
      updated: 0,
      last_id: after_id
    })
  end

  @spec sum_results(result(), result()) :: result()
  defp sum_results(first, second) do
    %{
      second
      | scanned: first.scanned + second.scanned,
        inserted: first.inserted + second.inserted,
        updated: first.updated + second.updated
    }
  end

  @spec copy_batches(:priority | :full, non_neg_integer(), pos_integer(), result()) :: result()
  defp copy_batches(phase, after_id, batch_size, totals) do
    case batch_upper_bound(phase, after_id, batch_size) do
      nil ->
        totals

      {upto, scanned} ->
        %{rows: rows} =
          Repo.query!(@copy_sql[phase], [after_id, upto],
            timeout: :infinity,
            skip_organization_id: true
          )

        inserted = Enum.count(rows, fn [inserted?] -> inserted? end)
        Logger.info("Contact identity backfill #{phase} pass reached contact #{upto}")

        totals = %{
          totals
          | scanned: totals.scanned + scanned,
            inserted: totals.inserted + inserted,
            updated: totals.updated + length(rows) - inserted,
            last_id: upto
        }

        if scanned < batch_size,
          do: totals,
          else: copy_batches(phase, upto, batch_size, totals)
    end
  end

  @spec batch_upper_bound(:priority | :full, non_neg_integer(), pos_integer()) ::
          {non_neg_integer(), non_neg_integer()} | nil
  defp batch_upper_bound(phase, after_id, batch_size) do
    %{rows: [[upto, scanned]]} =
      Repo.query!(
        """
        SELECT MAX(id), COUNT(*) FROM (
          SELECT c.id FROM contacts c
          WHERE c.id > $1 AND c.phone IS NOT NULL AND c.phone <> ''#{@batch_filter[phase]}
          ORDER BY c.id LIMIT $2
        ) batch
        """,
        [after_id, batch_size],
        skip_organization_id: true
      )

    if is_nil(upto), do: nil, else: {upto, scanned}
  end
end
