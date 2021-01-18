defmodule Glific.Jobs do
  @moduledoc """
  The Jobs context.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Jobs.BigqueryJob,
    Jobs.ChatbaseJob,
    Jobs.GcsJob,
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

  @doc """
  Gets a single job entry for the organization.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  @spec get_gcs_job(integer) :: GcsJob.t() | nil
  def get_gcs_job(organization_id),
    do:
      Repo.get_by(
        GcsJob,
        %{organization_id: organization_id}
      )

  @doc """
  Create or update a gcs_job with the message_id and
  organization_id
  """
  @spec upsert_gcs_job(map()) :: {:ok, GcsJob.t()} | {:error, Ecto.Changeset.t()}
  def upsert_gcs_job(attrs) do
    changeset = GcsJob.changeset(%GcsJob{}, attrs)

    Repo.insert!(
      changeset,
      returning: true,
      on_conflict: [set: [message_media_id: attrs.message_media_id]],
      conflict_target: :organization_id
    )
  end

  @doc false
  @spec get_bigquery_job(integer, String.t()) :: BigqueryJob.t() | nil
  def get_bigquery_job(organization_id, table),
    do:
      Repo.get_by(
        BigqueryJob,
        %{organization_id: organization_id, table: table}
      )

  @doc """
  Update a bigquery_job with the message_id and
  organization_id
  """
  @spec update_bigquery_job(BigqueryJob.t(), map()) ::
          {:ok, BigqueryJob.t()} | {:error, Ecto.Changeset.t()}
  def update_bigquery_job(%BigqueryJob{} = bigquery_job, attrs) do
    bigquery_job
    |> BigqueryJob.changeset(attrs)
    |> Repo.update()
  end

  @spec update_bigquery_job(non_neg_integer, String.t(), map()) ::
          {:ok, BigqueryJob.t()} | {:error, Ecto.Changeset.t()}
  def update_bigquery_job(organization_id, table, attrs),
  do: get_bigquery_job(organization_id, table)
    |> update_bigquery_job(attrs)

  @doc false
  @spec get_bigquery_jobs(integer) :: list() | nil
  def get_bigquery_jobs(organization_id) do
    BigqueryJob
    |> where([bg], bg.organization_id == ^organization_id)
    |> Repo.all()
  end
end
