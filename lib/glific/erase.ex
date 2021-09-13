defmodule Glific.Erase do
  @moduledoc """
  A simple module to periodically delete old data to clean up db
  """
  import Ecto.Query

  alias Glific.{
    Flows.WebhookLog,
    Notifications,
    Repo
  }
  @max_age 1
  @doc """
  This is called from the cron job on a regular schedule and cleans database periodically
  """
  @spec clean_db(non_neg_integer) :: :ok
  def clean_db(organization_id) do
    clean_notifications(organization_id)
    webhook_logs(organization_id)
    flow_revision(organization_id)
  end

  @doc """
  Deleting notification older than a month
  """
  @spec clean_notifications(non_neg_integer()) :: String.t()
  def clean_notifications(organization_id) do
    from n in Notification,
      where:
        n.inserted_at <
          ago(@max_age, "month")
          |> Repo.delete_all()
  end

  @doc """
  Deleting webhook_logs older than a month
  """
  @spec webhook_logs(non_neg_integer()) :: String.t()
  def webhook_logs(organization_id) do
    from w in WebhookLog,
      where:
        w.inserted_at <
          ago(@max_age, "month")
          |> Repo.delete_all()
  end

  @doc """
  Deleting flow_revision older than a month
  """
  @spec flow_revision(non_neg_integer()) :: String.t()
  def flow_revision(organization_id) do
    clean_drafted_flow_revisions()
    clean_drafted_archived_revisions()
  end

  defp clean_drafted_flow_revisions do
    """
    DELETE FROM flow_revisions fr1
    WHERE fr1.status = 'draft' AND id
    NOT IN( SELECT fr2.id FROM flow_revisions fr2 WHERE fr2.flow_id = fr1.flow_id and fr2.status = 'draft' ORDER BY fr2.id DESC LIMIT 10);
    """
    |> Repo.query!([], timeout: 60_000, skip_organization_id: true)
  end

  defp clean_drafted_archived_revisions do
    """
    DELETE FROM flow_revisions fr1
    WHERE fr1.status = 'archived' AND id
    NOT IN( SELECT fr2.id FROM flow_revisions fr2 WHERE fr2.flow_id = fr1.flow_id  and fr2.status = 'archived' ORDER BY fr2.id DESC LIMIT 10);
    """
    |> Repo.query!([], timeout: 60_000, skip_organization_id: true)
  end
end
