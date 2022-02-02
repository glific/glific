defmodule Glific.GCS do
  @moduledoc """
  Glific GCS Manager
  """

  @behaviour Waffle.Storage.Google.Token.Fetcher
  require Logger

  alias Glific.{
    GCS.GcsJob,
    Partners,
    Repo
  }

  alias Waffle.Storage.Google.CloudStorage

  @doc """
  Fetch token for GCS
  """
  @impl Waffle.Storage.Google.Token.Fetcher
  @spec get_token(binary) :: binary
  def get_token(organization_id) when is_binary(organization_id) do
    Logger.info("fetching gcs token for org_id: #{organization_id}")
    organization_id = String.to_integer(organization_id)
    token = Partners.get_goth_token(organization_id, "google_cloud_storage")

    if is_nil(token),
      do: Logger.info("error while fetching the gcs token org_id: #{organization_id}"),
      else: token.token
  end

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec refresh_gcs_setup(non_neg_integer) :: :ok
  def refresh_gcs_setup(organization_id) do
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

  @spec upload_file(String.t(), String.t(), non_neg_integer) ::
          {:ok, GoogleApi.Storage.V1.Model.Object.t()} | {:error, Tesla.Env.t()} | {:error, map()}
  def upload_file(local, remote, organization_id) do
    Logger.info("Uploading to GCS, org_id: #{organization_id}, file_name: #{remote}")

    CloudStorage.put(
      Glific.PrivateMedia,
      :original,
      {%Waffle.File{path: local, file_name: remote}, "#{organization_id}"}
    )
    |> case do
      {:ok, response} ->
        {:ok, response}

      {:error, error} when is_map(error) == true ->
        {:error, error}

      response ->
        {:error, %{body: response}}
    end
  end

  @spec download_file_to_temp(String.t(), String.t(), non_neg_integer) ::
          {:ok, String.t()} | {:error, any()}
  def download_file_to_temp(url, path, org_id) do
    Logger.info("Downloading file: org_id: #{org_id}, url: #{url}")

    Tesla.get(url)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body} = _env} when status in 200..299 ->
        File.write!(path, body)
        {:ok, path}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error, reason}

      error ->
        {:error, error}
    end
  end

  @doc """
  Generate a sigend url for a private file
  """
  @spec get_signed_url(String.t(), non_neg_integer, keyword) :: String.t()
  def get_signed_url(file_name, organization_id, opts \\ []) do
    Repo.put_organization_id(organization_id)
    Partners.get_goth_token(organization_id, "google_cloud_storage")

    opts =
      [signed: true, expires_in: 300]
      |> Keyword.merge(opts)

    CloudStorage.url(
      Glific.PrivateMedia,
      :original,
      {%Waffle.File{file_name: file_name}, "#{organization_id}"},
      opts
    )
  end
end
