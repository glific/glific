defmodule Glific.Scripts.RestoreContactWhatsappState do
  @moduledoc """
  Rollback safety for the move of a contact's WhatsApp opt-in, opt-out, BSP status and last inbound
  message from `contacts` to its `(whatsapp, phone)` contact identity.

  The release stopped writing those `contacts` columns. If it is rolled back, the previous code reads
  them again and would miss every opt-in, opt-out and session change made since. This copies the
  identity values back onto `contacts`, across all organizations, in batches of identities.

  Only an identity that records consent is copied back whole. A row created since the release by a write that
  carried no consent, such as an inbound message or a phone change, holds defaults (not opted in, no times) and
  would overwrite a real opt-in or opt-out still on `contacts`; the same test as the backfill's decides, so
  a row that has been through the backfill is never mistaken for one that has not. Such a row only moves the
  session forward: `last_message_at` becomes the later of the two times and a `session` status is added to the
  contact's own `bsp_status`. Contacts without a WhatsApp identity row are left alone: their columns are still
  current.

  Only contacts whose columns would change are written, so it is idempotent and cheap to run twice.
  Run it after the new code has stopped serving traffic, so nothing changes underneath it.

  ## Run from IEx (`gigalixir remote_console`)

      iex> Glific.Scripts.RestoreContactWhatsappState.run()
      %{updated: 412_000, last_id: 7_123_456}

      # resume after an interrupted run, from the last id it logged
      iex> Glific.Scripts.RestoreContactWhatsappState.run(after_id: 3_000_000)
  """

  require Logger

  alias Glific.{Contacts.IdentityBackfill, Repo}

  @default_batch_size 5_000

  @typedoc "What a run did, and the id to resume from."
  @type result :: %{updated: non_neg_integer(), last_id: non_neg_integer()}

  @copy_sql """
  WITH target AS (
    SELECT c.id,
      r.recorded,
      CASE WHEN r.recorded THEN i.optin_time ELSE c.optin_time END AS optin_time,
      CASE WHEN r.recorded THEN i.optin_status ELSE COALESCE(c.optin_status, false) END AS optin_status,
      CASE WHEN r.recorded THEN i.optin_method ELSE c.optin_method END AS optin_method,
      CASE WHEN r.recorded THEN i.optout_time ELSE c.optout_time END AS optout_time,
      CASE WHEN r.recorded THEN i.optout_method ELSE c.optout_method END AS optout_method,
      CASE
        WHEN r.recorded THEN i.bsp_status
        WHEN i.bsp_status IN ('session', 'session_and_hsm') AND c.bsp_status = 'none' THEN 'session'
        WHEN i.bsp_status IN ('session', 'session_and_hsm') AND c.bsp_status = 'hsm' THEN 'session_and_hsm'
        ELSE c.bsp_status
      END AS bsp_status,
      GREATEST(c.last_message_at, i.last_message_at) AS last_message_at
    FROM contacts c
    JOIN contact_identities i
      ON i.contact_id = c.id AND i.channel = 'whatsapp' AND i.identifier = c.phone
    CROSS JOIN LATERAL (SELECT NOT #{IdentityBackfill.consent_unrecorded_sql()} AS recorded) r
    WHERE c.id > $1 AND c.id <= $2
  )
  UPDATE contacts c SET
    optin_time = t.optin_time,
    optin_status = t.optin_status,
    optin_method = t.optin_method,
    optout_time = t.optout_time,
    optout_method = t.optout_method,
    bsp_status = t.bsp_status,
    last_message_at = t.last_message_at
  FROM target t
  WHERE c.id = t.id
    AND (c.optin_time, c.optin_status, c.optin_method, c.optout_time, c.optout_method,
         c.bsp_status, c.last_message_at)
        IS DISTINCT FROM
        (t.optin_time, t.optin_status, t.optin_method, t.optout_time, t.optout_method,
         t.bsp_status, t.last_message_at)
  """

  @doc """
  Copies the WhatsApp state of every contact with an id above `:after_id` (default 0) back onto `contacts`,
  `:batch_size` identities at a time.
  """
  @spec run(Keyword.t()) :: result()
  def run(opts \\ []) do
    after_id = Keyword.get(opts, :after_id, 0)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    copy_batches(after_id, batch_size, %{updated: 0, last_id: after_id})
  end

  @spec copy_batches(non_neg_integer(), pos_integer(), result()) :: result()
  defp copy_batches(after_id, batch_size, totals) do
    case last_contact_id_of_batch(after_id, batch_size) do
      nil ->
        totals

      upto ->
        %{num_rows: updated} =
          Repo.query!(@copy_sql, [after_id, upto], timeout: :infinity, skip_organization_id: true)

        Logger.info("Contact WhatsApp state restore reached contact #{upto}")

        copy_batches(upto, batch_size, %{updated: totals.updated + updated, last_id: upto})
    end
  end

  @spec last_contact_id_of_batch(non_neg_integer(), pos_integer()) :: non_neg_integer() | nil
  defp last_contact_id_of_batch(after_id, batch_size) do
    %{rows: [[upto]]} =
      Repo.query!(
        """
        SELECT MAX(contact_id) FROM (
          SELECT contact_id FROM contact_identities
          WHERE channel = 'whatsapp' AND contact_id > $1
          ORDER BY contact_id LIMIT $2
        ) batch
        """,
        [after_id, batch_size],
        skip_organization_id: true
      )

    upto
  end
end
