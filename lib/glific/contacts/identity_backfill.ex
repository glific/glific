defmodule Glific.Contacts.IdentityBackfill do
  @moduledoc """
  One-off copy of the old `contacts` consent and session columns (opt-in, opt-out, BSP status, last inbound
  message) onto each contact's `(whatsapp, phone)` identity, creating the identity where it is missing. It
  lives under `lib/glific/contacts/` because it writes `ContactIdentity` rows; nothing in the application
  calls it.

  The application reads those fields from identities only, so run it right after the deploy. It is set-based:
  contacts are walked in id ranges of `batch_size` with partial phones skipped, and each range is a single
  `INSERT ... SELECT ... ON CONFLICT` statement, so no lock outlives a batch and a rerun is safe.

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

      # resume after an interrupted run, from the last id it logged
      iex> Glific.Contacts.IdentityBackfill.run(after_id: 3_000_000)
  """

  require Logger

  alias Glific.Repo

  @default_batch_size 10_000

  @typedoc "What a run did, and the id to resume from."
  @type result :: %{
          scanned: non_neg_integer(),
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          last_id: non_neg_integer()
        }

  @consent_unrecorded """
  (i.optin_time IS NULL AND i.optout_time IS NULL AND i.optin_method IS NULL
   AND i.optout_method IS NULL AND NOT i.optin_status)
  """

  @merged_bsp_status """
  CASE
    WHEN NOT #{@consent_unrecorded} THEN i.bsp_status
    WHEN i.bsp_status = 'none' THEN EXCLUDED.bsp_status
    WHEN i.bsp_status = 'session' AND EXCLUDED.optin_time IS NOT NULL THEN 'session_and_hsm'
    ELSE i.bsp_status
  END
  """

  @copy_sql """
  INSERT INTO contact_identities AS i
    (contact_id, organization_id, channel, identifier, optin_time, optin_status, optin_method,
     optout_time, optout_method, bsp_status, last_message_at, inserted_at, updated_at)
  SELECT c.id, c.organization_id, 'whatsapp', c.phone, c.optin_time, COALESCE(c.optin_status, false),
         c.optin_method, c.optout_time, c.optout_method, COALESCE(c.bsp_status, 'none'),
         c.last_message_at, now(), now()
  FROM contacts c
  WHERE c.id > $1 AND c.id <= $2 AND c.phone IS NOT NULL AND c.phone <> ''
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

  @doc """
  Copies every contact with an id above `:after_id` (default 0), `:batch_size` contacts at a time.
  """
  @spec run(Keyword.t()) :: result()
  def run(opts \\ []) do
    after_id = Keyword.get(opts, :after_id, 0)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    copy_batches(after_id, batch_size, %{scanned: 0, inserted: 0, updated: 0, last_id: after_id})
  end

  @spec copy_batches(non_neg_integer(), pos_integer(), result()) :: result()
  defp copy_batches(after_id, batch_size, totals) do
    case batch_upper_bound(after_id, batch_size) do
      nil ->
        totals

      {upto, scanned} ->
        %{rows: rows} =
          Repo.query!(@copy_sql, [after_id, upto], timeout: :infinity, skip_organization_id: true)

        inserted = Enum.count(rows, fn [inserted?] -> inserted? end)
        Logger.info("Contact identity backfill reached contact #{upto}")

        totals = %{
          scanned: totals.scanned + scanned,
          inserted: totals.inserted + inserted,
          updated: totals.updated + length(rows) - inserted,
          last_id: upto
        }

        if scanned < batch_size, do: totals, else: copy_batches(upto, batch_size, totals)
    end
  end

  @spec batch_upper_bound(non_neg_integer(), pos_integer()) ::
          {non_neg_integer(), non_neg_integer()} | nil
  defp batch_upper_bound(after_id, batch_size) do
    %{rows: [[upto, scanned]]} =
      Repo.query!(
        """
        SELECT MAX(id), COUNT(*) FROM (
          SELECT id FROM contacts
          WHERE id > $1 AND phone IS NOT NULL AND phone <> ''
          ORDER BY id LIMIT $2
        ) batch
        """,
        [after_id, batch_size],
        skip_organization_id: true
      )

    if is_nil(upto), do: nil, else: {upto, scanned}
  end
end
