defmodule Glific.Scripts.RestoreContactWhatsappState do
  @moduledoc """
  Rollback safety for the move of a contact's WhatsApp opt-in, opt-out, BSP status and last inbound
  message from `contacts` to its `(whatsapp, phone)` contact identity.

  The release stopped writing those `contacts` columns. If it is rolled back, the previous code reads
  them again and would miss every opt-in, opt-out and session change made since. This copies the
  identity values back onto `contacts`, across all organizations, in batches of identities.

  Only contacts whose columns differ from their identity are written, so it is idempotent and cheap to
  run twice. Contacts without a WhatsApp identity row are left alone: their columns are still current.
  Run it after the new code has stopped serving traffic, so nothing changes underneath it.

  ## Run from IEx (`gigalixir remote_console`)

      iex> Glific.Scripts.RestoreContactWhatsappState.run()
      %{updated: 412_000, last_id: 7_123_456}

      # resume after an interrupted run, from the last id it logged
      iex> Glific.Scripts.RestoreContactWhatsappState.run(after_id: 3_000_000)
  """

  require Logger

  alias Glific.Repo

  @default_batch_size 5_000

  @typedoc "What a run did, and the id to resume from."
  @type result :: %{updated: non_neg_integer(), last_id: non_neg_integer()}

  @copy_sql """
  UPDATE contacts c SET
    optin_time = i.optin_time,
    optin_status = i.optin_status,
    optin_method = i.optin_method,
    optout_time = i.optout_time,
    optout_method = i.optout_method,
    bsp_status = i.bsp_status,
    last_message_at = i.last_message_at
  FROM contact_identities i
  WHERE c.id > $1 AND c.id <= $2
    AND i.contact_id = c.id AND i.channel = 'whatsapp' AND i.identifier = c.phone
    AND (c.optin_time, c.optin_status, c.optin_method, c.optout_time, c.optout_method,
         c.bsp_status, c.last_message_at)
        IS DISTINCT FROM
        (i.optin_time, i.optin_status, i.optin_method, i.optout_time, i.optout_method,
         i.bsp_status, i.last_message_at)
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
