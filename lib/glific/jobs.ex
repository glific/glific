defmodule Glific.Jobs do
  @moduledoc """
  The Jobs context.
  """
  import Ecto.Query, warn: false

  alias Glific.{
    BigQuery.BigQueryJob,
    GCS.GcsJob,
    Repo
  }

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
  @spec update_gcs_job(map()) :: {:ok, GcsJob.t()} | {:error, Ecto.Changeset.t()}
  def update_gcs_job(attrs) do
    case Repo.get_by(GcsJob, %{organization_id: attrs.organization_id}) do
      nil ->
        GcsJob.changeset(%GcsJob{}, attrs)
        |> Repo.insert()

      gcs_job ->
        gcs_job
        |> GcsJob.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc false
  @spec get_bigquery_job(integer, String.t()) :: BigQueryJob.t() | nil
  def get_bigquery_job(organization_id, table),
    do:
      Repo.get_by(
        BigQueryJob,
        %{organization_id: organization_id, table: table}
      )

  @doc """
  Update a bigquery_job with the message_id and
  organization_id
  """
  @spec update_bigquery_job(BigQueryJob.t(), map()) ::
          {:ok, BigQueryJob.t()} | {:error, Ecto.Changeset.t()}
  def update_bigquery_job(%BigQueryJob{} = bigquery_job, attrs) do
    bigquery_job
    |> BigQueryJob.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Update a bigquery_job table
  """
  @spec update_bigquery_job(non_neg_integer, String.t(), map()) ::
          {:ok, BigQueryJob.t()} | {:error, Ecto.Changeset.t()}
  def update_bigquery_job(organization_id, table, attrs),
    do:
      get_bigquery_job(organization_id, table)
      |> update_bigquery_job(attrs)

  @doc false
  @spec get_bigquery_jobs(integer) :: list() | nil
  def get_bigquery_jobs(organization_id) do
    BigQueryJob
    |> where([bg], bg.organization_id == ^organization_id)
    |> Repo.all()
  end
end
