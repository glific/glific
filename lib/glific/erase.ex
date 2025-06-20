defmodule Glific.Erase do
  @moduledoc """
  A simple module to periodically delete old data to clean up db
  """
  import Ecto.Query

  alias Glific.Contacts.Contact
  alias Glific.Repo
  require Logger

  use Oban.Worker,
    queue: :purge,
    max_attempts: 1

  @batch_sleep 1_000
  @no_of_months 2

  @doc """
  Do the weekly DB cleaner tasks, typically in the middle of the night on sunday morning
  """
  @spec perform_weekly() :: any
  def perform_weekly do
    clean_old_records()
    refresh_tables()
  end

  @doc """
  Creates an Oban job for purging old messages in batch

  - batch_size - size of a batch (limit in select query)
  - max_rows_to_delete - Maximum rows to delete weekly
  - sleep_after_delete? - sleeps for 1 sec if true.
  """
  @spec perform_message_purge(number() | nil, number() | nil, boolean()) :: tuple()
  def perform_message_purge(
        batch_size \\ nil,
        max_rows_to_delete \\ nil,
        sleep_after_delete? \\ true
      ) do
    purge_config = Application.get_env(:glific, Glific.Erase)

    batch_size =
      batch_size ||
        Keyword.get(purge_config, :msg_delete_batch_size) |> Glific.parse_maybe_integer!()

    max_rows_to_delete =
      max_rows_to_delete ||
        Keyword.get(purge_config, :max_msg_rows_to_delete) |> Glific.parse_maybe_integer!()

    __MODULE__.new(%{
      batch_size: batch_size,
      max_rows_to_delete: max_rows_to_delete,
      sleep_after_delete?: sleep_after_delete?
    })
    |> Oban.insert()
  end

  @doc """
  Do the daily DB cleaner tasks
  """
  @spec perform_daily() :: any
  def perform_daily do
    [
      "REINDEX TABLE global.oban_jobs"
    ]
    |> Enum.each(&Repo.query!(&1, [], timeout: 300_000, skip_organization_id: true))
  end

  @doc """
  Clean old records for table like notification and logs
  """
  @spec clean_old_records() :: any
  def clean_old_records do
    remove_old_records()
    clean_flow_revision()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "batch_size" => batch_size,
          "max_rows_to_delete" => max_rows_to_delete,
          "sleep_after_delete?" => sleep_after_delete?
        }
      }) do
    delete_old_messages(batch_size, max_rows_to_delete, sleep_after_delete?)
  end

  @spec refresh_tables() :: any
  defp refresh_tables do
    [
      "REINDEX TABLE global.oban_jobs",
      "VACUUM (FULL, ANALYZE) webhook_logs",
      "VACUUM (FULL, ANALYZE) organizations",
      "VACUUM (FULL, ANALYZE) messages_tags",
      "VACUUM (FULL, ANALYZE) notifications",
      "VACUUM (FULL, ANALYZE) flow_counts",
      "VACUUM (FULL, ANALYZE) bigquery_jobs",
      "VACUUM (FULL, ANALYZE) global.oban_producers",
      "VACUUM (FULL, ANALYZE) contacts_groups",
      "VACUUM (FULL, ANALYZE) flow_results",
      "VACUUM (FULL, ANALYZE) contacts",
      "VACUUM (FULL, ANALYZE) contact_histories",
      "VACUUM (ANALYZE) messages",
      "VACUUM (ANALYZE) messages_media"
    ]
    |> Enum.each(
      # need such a large timeout specifically to vacuum the messages
      &Repo.query!(&1, [], timeout: 1_000_000, skip_organization_id: true)
    )
  end

  # Deleting rows older than a month from tables periodically
  @spec remove_old_records() :: any
  defp remove_old_records do
    [
      {"message_broadcasts", "week"},
      {"notifications", "week"},
      {"webhook_logs", "week"},
      {"flow_contexts", "month"},
      {"flow_results", "month"},
      {"messages_conversations", "month"},
      {"user_jobs", "month"},
      {"issued_certificates", "month"}
    ]
    |> Enum.each(fn {table, duration} ->
      Repo.delete_all(
        from(fc in table,
          where: fc.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^duration)
        ),
        skip_organization_id: true,
        timeout: 400_000
      )
    end)
  end

  @doc """
  Keep latest 25 contact_history for a contact
  """
  @spec clean_contact_histories() :: any
  def clean_contact_histories do
    """
    WITH top_25_contact_histories_per_contact AS (
    SELECT t.*, ROW_NUMBER() OVER (PARTITION BY contact_id ORDER BY updated_at DESC) rn
    FROM contact_histories t
    )
    DELETE FROM contact_histories WHERE id NOT IN (
      SELECT id
      FROM top_25_contact_histories_per_contact
      WHERE rn <= 25
    )
    """
    |> Repo.query!([], timeout: 60_000, skip_organization_id: true)
  end

  # Deleting flow_revision older than a month
  @spec clean_flow_revision() :: any
  defp clean_flow_revision do
    clean_drafted_flow_revisions()
    clean_archived_flow_revisions()
  end

  defp clean_drafted_flow_revisions do
    """
    DELETE FROM flow_revisions fr1
    WHERE fr1.status = 'draft' AND id
    NOT IN( SELECT fr2.id FROM flow_revisions fr2 WHERE fr2.flow_id = fr1.flow_id and fr2.status = 'draft' ORDER BY fr2.id DESC LIMIT 10);
    """
    |> Repo.query!([], timeout: 60_000, skip_organization_id: true)
  end

  defp clean_archived_flow_revisions do
    """
    DELETE FROM flow_revisions fr1
    WHERE fr1.status = 'archived' AND id
    NOT IN( SELECT fr2.id FROM flow_revisions fr2 WHERE fr2.flow_id = fr1.flow_id  and fr2.status = 'archived' ORDER BY fr2.id DESC LIMIT 10);
    """
    |> Repo.query!([], timeout: 60_000, skip_organization_id: true)
  end

  @limit 250

  @doc """
  Keep latest limited messages for a contact
  """
  @spec clean_messages(non_neg_integer, non_neg_integer) :: list
  def clean_messages(org_id, limit \\ @limit) do
    Repo.put_process_state(org_id)

    contact_query = """
    SELECT id,
           last_message_number,
           first_message_number,
           last_message_number - first_message_number as cnt
    FROM contacts
    WHERE organization_id = #{org_id}
      AND first_message_number IS NOT NULL
      AND last_message_number - first_message_number > #{limit + 2}
    ORDER BY cnt desc
    LIMIT 200
    """

    Repo.query!(contact_query).rows
    |> Enum.map(fn [contact_id | opts] ->
      clean_message_for_contact(contact_id, org_id, limit, opts)
    end)
  end

  @doc """
  Keep latest limited messages for a contact
  """
  @spec clean_message_for_contact(
          non_neg_integer,
          non_neg_integer,
          non_neg_integer,
          list()
        ) :: :ok
  def clean_message_for_contact(contact_id, org_id, limit, opts) do
    [last_message_number, first_message_number, count] = opts

    message_to_delete = last_message_number - limit

    # make sure we keep a few messages around
    if count > 3 &&
         message_to_delete > 0 &&
         message_to_delete > first_message_number + 3 do
      delete_media_query = """
      DELETE
      FROM messages_media
      WHERE id IN (
        SELECT media_id
        FROM messages m
        WHERE
          m.media_id IS NOT NULL
          AND m.contact_id = #{contact_id}
          AND m.organization_id = #{org_id}
          AND m.message_number < #{message_to_delete}
          and m.flow = 'inbound'
      )
      """

      delete_message_query = """
      DELETE
      FROM messages
      WHERE organization_id = #{org_id}
      AND contact_id = #{contact_id}
      AND message_number < #{message_to_delete}
      """

      update_contact_query = """
      UPDATE contacts
      SET first_message_number = #{message_to_delete}
      WHERE id = #{contact_id}
      AND organization_id = #{org_id}
      """

      Logger.info(
        "Deleting messages for #{contact_id} where message number < #{message_to_delete}"
      )

      [delete_media_query, delete_message_query, update_contact_query]
      |> Enum.each(fn query ->
        # Logger.info("QUERY: #{query}")
        Repo.query!(query, [], timeout: 400_000, skip_organization_id: true)
      end)
    end

    :ok
  end

  @doc """
  Deletes all the data related to a contact
  """
  @spec delete_benefeciary_data(non_neg_integer(), String.t()) :: any()
  def delete_benefeciary_data(org_id, phone) do
    get_value =
      if Application.get_env(:glific, :environment) in [:prod, :dev] do
        Task.async(fn ->
          IO.gets(
            "Are you sure want to delete data for #{phone} of org_id #{org_id}\nPress Y or y to continue, auto aborts if idle for 10s\n"
          )
        end)
        |> Task.await(10_000)
      else
        "y"
      end

    Repo.put_process_state(org_id)

    with "y" <- String.trim_trailing(get_value, "\n") |> String.downcase(),
         {:ok, contact} <- Repo.fetch_by(Contact, %{phone: phone}) do
      Logger.warning(
        "Deleting beneficiary data for contact #{phone} and organization_id #{org_id}"
      )

      delete_messages_query = """
      DELETE FROM messages where organization_id = #{org_id} and contact_id = #{contact.id}
      """

      delete_contact_query =
        """
        DELETE FROM contacts where organization_id = #{org_id}  and id = #{contact.id}
        """

      [delete_messages_query, delete_contact_query]
      |> Enum.each(fn query ->
        Repo.query!(query, [], timeout: 400_000, skip_organization_id: true)
      end)

      Logger.info("Deleted beneficiary data for contact #{phone} and organization_id #{org_id}")

      :ok
    end
  end

  @spec delete_old_messages(number(), number(), boolean(), number()) :: any()
  defp delete_old_messages(
         batch_size,
         max_rows_to_delete,
         sleep_after_delete?,
         total_rows_deleted \\ 0
       )
       when is_number(batch_size) and is_number(max_rows_to_delete) do
    time_before_delete = DateTime.utc_now()

    {:ok, %{num_rows: rows_deleted}} =
      try do
        """
        WITH rows_to_delete AS (
        SELECT id FROM messages
        WHERE inserted_at <= CURRENT_DATE - interval '#{@no_of_months} months'
        ORDER BY id
        LIMIT #{batch_size}
        )
        DELETE FROM messages
        WHERE id IN (SELECT id FROM rows_to_delete);
        """
        |> Repo.query([], timeout: 400_000, skip_organization_id: true)
      rescue
        err ->
          Logger.error("Messages purge timed out #{inspect(err)}")
          {:ok, %{num_rows: 0}}
      end

    total_rows_deleted = total_rows_deleted + rows_deleted
    time_after_delete = DateTime.diff(DateTime.utc_now(), time_before_delete)

    if rows_deleted < batch_size or total_rows_deleted >= max_rows_to_delete do
      Logger.info(
        "Total rows deleted: #{total_rows_deleted}, time taken for this batch: #{time_after_delete} s"
      )

      {:ok, total_rows_deleted}
    else
      # deleting the next batch after a second, to ease the DB load
      if sleep_after_delete? do
        Process.sleep(@batch_sleep)
      end

      delete_old_messages(
        batch_size,
        max_rows_to_delete,
        sleep_after_delete?,
        total_rows_deleted
      )
    end
  end
end
