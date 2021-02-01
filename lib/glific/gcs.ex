defmodule Glific.GCS do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  @behaviour Waffle.Storage.Google.Token.Fetcher
  require Logger

  alias Glific.{
    Jobs.GcsJob,
    Partners,
    Repo
  }

  @doc """
  Fetch token for GCS
  """
  @impl Waffle.Storage.Google.Token.Fetcher
  @spec get_token(binary) :: binary
  def get_token(organization_id) when is_binary(organization_id) do
    Logger.info("fetching gcs token for org_id: #{organization_id}")
    organization_id = String.to_integer(organization_id)
    token = Partners.get_goth_token(organization_id, "google_cloud_storage")
    token.token
  end


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
