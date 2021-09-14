defmodule Glific.Erase do
  @moduledoc """
  A simple module to periodically delete old data to clean up db
  """
  import Ecto.Query

  alias Glific.Repo

  @period "month"
  @doc """
  This is called from the cron job on a regular schedule and cleans database periodically
  """
  @spec perform_periodic() :: :ok
  def perform_periodic do
    clean_notifications()
    clean_webhook_logs()
    clean_flow_revision()
    :ok
  end

  @doc """
  Deleting notification older than a month
  """
  @spec clean_notifications() :: {integer(), nil | [term()]}
  def clean_notifications do
    Repo.delete_all(
      from(n in "notifications",
        where: n.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^@period)
      ),
      skip_organization_id: true
    )
  end

  @doc """
  Deleting webhook logs older than a month
  """
  @spec clean_webhook_logs() :: {integer(), nil | [term()]}
  def clean_webhook_logs do
    Repo.delete_all(
      from(w in "webhook_logs",
        where: w.inserted_at < fragment("CURRENT_DATE - ('1' || ?)::interval", ^@period)
      ),
      skip_organization_id: true
    )
  end

  @doc """
  Deleting flow_revision older than a month
  """
  @spec clean_flow_revision() :: :ok
  def clean_flow_revision do
    clean_drafted_flow_revisions()
    clean_archived_flow_revisions()
    :ok
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
end
