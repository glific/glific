defmodule Glific.Erase do
  @moduledoc """
  A simple module to periodically delete old data to clean up db
  """
  import Ecto.Query

  alias Glific.Repo

  alias Glific.Seeds.SeedsMigration

  require Logger

  @period "month"

  @doc """
  This is called from the cron job on a regular schedule and cleans database periodically
  """
  @spec perform_periodic() :: any
  def perform_periodic do
    clean_notifications()
    clean_webhook_logs()
    clean_flow_revision()
    clean_flow_contexts()
    clean_contact_histories()
    clean_message_conversations()
  end

  # Deleting notification older than a month
  @spec clean_notifications() :: {integer(), nil | [term()]}
  defp clean_notifications do
    Repo.delete_all(
      from(n in "notifications",
        where: n.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^@period)
      ),
      skip_organization_id: true
    )
  end

  # Deleting webhook logs older than a month
  @spec clean_webhook_logs() :: {integer(), nil | [term()]}
  defp clean_webhook_logs do
    Repo.delete_all(
      from(w in "webhook_logs",
        where: w.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^@period)
      ),
      skip_organization_id: true
    )
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

  defp clean_flow_contexts do
    Repo.delete_all(
      from(fc in "flow_contexts",
        where: fc.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^@period)
      ),
      skip_organization_id: true
    )
  end

  defp clean_contact_histories do
    Repo.delete_all(
      from(fc in "contact_histories",
        where: fc.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^@period)
      ),
      skip_organization_id: true
    )
  end

  defp clean_message_conversations do
    Repo.delete_all(
      from(mc in "messages_conversations",
        where: mc.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^@period)
      ),
      skip_organization_id: true
    )
  end

  @limit 200

  @doc """
  Keep latest 200 messages for a contact
  """
  @spec clean_old_messages(non_neg_integer(), boolean()) :: list
  def clean_old_messages(org_id, skip_delete \\ false) do
    contact_query =
      "select id from contacts where organization_id = #{org_id} and last_message_number > #{@limit + 2} order by last_message_number"

    Repo.query!(contact_query).rows
    |> Enum.map(fn [contact_id] ->
      clean_old_message_for_contact(contact_id, org_id, skip_delete)
    end)
  end

  @doc """
  Keep latest 200 messages for a contact
  """
  @spec clean_old_message_for_contact(non_neg_integer(), non_neg_integer(), boolean()) :: :ok
  def clean_old_message_for_contact(contact_id, org_id, skip_delete \\ false) do
    SeedsMigration.fix_message_number_for_contact(contact_id)

    [[last_message_number]] =
      Glific.Repo.query!("select last_message_number from contacts where id = #{contact_id}").rows

    message_to_delete = last_message_number - @limit

    delete_message_query =
      "delete from messages where organization_id = #{org_id} and contact_id = #{contact_id} and message_number < #{message_to_delete}"

    Logger.info(
      "message cleanup started for #{contact_id} where message number #{message_to_delete}"
    )

    if skip_delete == false && message_to_delete > 0 do
      Repo.query!(delete_message_query, [], timeout: 400_000, skip_organization_id: true)
      SeedsMigration.fix_message_number_for_contact(contact_id)
    end

    :ok
  end

  @doc """
  Do the weekly DB cleaner tasks, typically in the middle of the night on sunday morning
  """
  @spec perform_weekly() :: any
  def perform_weekly do
    [
      "VACUUM (FULL, ANALYZE) webhook_logs",
      "VACUUM (FULL, ANALYZE) organizations",
      "VACUUM (FULL, ANALYZE) messages_tags",
      "VACUUM (FULL, ANALYZE) notifications",
      "VACUUM (FULL, ANALYZE) flow_counts",
      "VACUUM (FULL, ANALYZE) bigquery_jobs",
      "VACUUM (FULL, ANALYZE) global.oban_producers",
      "REINDEX TABLE global.oban_jobs",
      "VACUUM (FULL, ANALYZE) contacts_groups",
      "VACUUM (FULL, ANALYZE) flow_results",
      "VACUUM (FULL, ANALYZE) contacts",
      "VACUUM (ANALYZE) messages"
    ]
    |> Enum.each(
      # need such a large timeout specifically to vacuum the messages
      &Repo.query!(&1, [], timeout: 300_000, skip_organization_id: true)
    )
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
end
