defmodule Glific.Erase do
  @moduledoc """
  A simple module to periodically delete old data to clean up db
  """
  import Ecto.Query

  alias Glific.Repo

  require Logger

  @doc """
  Do the weekly DB cleaner tasks, typically in the middle of the night on sunday morning
  """
  @spec perform_weekly() :: any
  def perform_weekly do
    refresh_tables()
    clean_old_records()
  end

  @doc """
  Do the daily DB cleaner tasks
  """
  @spec perform_daily() :: any
  def perform_daily do
    [
      "REINDEX TABLE global.oban_jobs"
    ]
    |> Enum.each(
      # need such a large timeout specifically to vacuum the messages
      &Repo.query!(&1, [], timeout: 300_000, skip_organization_id: true)
    )
  end

  @doc """
  Clean old records for table like notification and logs
  """
  @spec clean_old_records() :: any
  def clean_old_records do
    remove_old_records()
    clean_flow_revision()
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
      &Repo.query!(&1, [], timeout: 300_000, skip_organization_id: true)
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
      {"messages_conversations", "month"}
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

  @limit 400

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
    [last_message_number, first_message_number, _count] = opts

    message_to_delete = last_message_number - limit

    # make sure we keep a few messages around
    if message_to_delete > 0 and message_to_delete > first_message_number + 2 do
      delete_message_query = """
      DELETE
      FROM messages
      WHERE organization_id = #{org_id}
      AND contact_id = #{contact_id}
      AND message_number < #{message_to_delete}
      """

      update_contact_query = """
      UPDATE contacts
      SET first_message_number = #{first_message_number + limit}
      WHERE contact_id = #{contact_id}
      AND organization_id = #{org_id}
      """

      Logger.info(
        "Deleting messages for #{contact_id} where message number < #{message_to_delete}"
      )

      Repo.query!(delete_message_query, [], timeout: 400_000, skip_organization_id: true)
      Repo.query!(update_contact_query, [], skip_organization_id: true)
    end

    :ok
  end
end
