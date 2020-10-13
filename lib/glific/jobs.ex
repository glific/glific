defmodule Glific.Jobs do
  @moduledoc """
  The Jobs context.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Jobs.BigqueryJob,
    Jobs.ChatbaseJob,
    Repo
  }

  @doc """
  Gets a single job entry for the organization.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_chatbase_job(integer) :: ChatbaseJob.t() | nil
  def get_chatbase_job(organization_id),
    do:
      Repo.get_by(
        ChatbaseJob,
        %{organization_id: organization_id}
      )

  @doc """
  Create or update a chatbase_job with the message_id and
  organization_id
  """
  @spec upsert_chatbase_job(map()) :: {:ok, ChatbaseJob.t()} | {:error, Ecto.Changeset.t()}
  def upsert_chatbase_job(attrs) do
    changeset = ChatbaseJob.changeset(%ChatbaseJob{}, attrs)

    Repo.insert!(
      changeset,
      returning: true,
      on_conflict: [set: [message_id: attrs.message_id]],
      conflict_target: :organization_id
    )
  end

  @spec get_bigquery_job(integer, String.t()) :: BigqueryJob.t() | nil
  def get_bigquery_job(organization_id, table),
    do:
     Repo.get_by(
        BigqueryJob,
        %{organization_id: organization_id, table: table }
      )

  @doc """
  Create or update a chatbase_job with the message_id and
  organization_id
  """
  @spec upsert_bigquery_job(map()) :: {:ok, BigqueryJob.t()} | {:error, Ecto.Changeset.t()}
  def upsert_bigquery_job(attrs) do
    changeset = BigqueryJob.changeset(%BigqueryJob{}, attrs)
    Repo.insert!(
      changeset,
      returning: true,
      on_conflict: [set: [table_id: attrs.table_id]],
      conflict_target: :organization_id
    )
  end


end
