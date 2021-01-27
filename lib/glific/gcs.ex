defmodule Glific.GCS do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  require Logger

  alias Glific.{
    Jobs.GcsJob,
    Repo
  }

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec refresh_gsc_setup(non_neg_integer) :: :ok
  def refresh_gsc_setup(organization_id) do
    Logger.info("refresh GCS setup for org_id: #{organization_id}")

    organization_id
    |> insert_gcs_jobs()

    :ok
  end

  @doc false
  @spec insert_gcs_jobs(non_neg_integer) :: :ok
  def insert_gcs_jobs(organization_id) do
    Repo.fetch_by(GcsJob, %{organization_id: organization_id})
    |> case do
      {:ok, gcs_job} ->
        gcs_job

      _ ->
        %GcsJob{organization_id: organization_id}
        |> Repo.insert!()
    end

    :ok
  end
end
