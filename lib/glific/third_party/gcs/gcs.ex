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

  @gcs_bucket_key {__MODULE__, :bucket_id}

  @doc """
  Put bucket name to the process
  """
  @spec get_bucket_name() :: String.t() | nil
  def get_bucket_name,
    do: Process.get(@gcs_bucket_key)

  @doc """
  get bucket name from the process
  """
  @spec put_bucket_name(String.t()) :: String.t() | nil
  def put_bucket_name(bucket_name),
    do: Process.put(@gcs_bucket_key, bucket_name)

  @spec get_secrets(non_neg_integer()) :: map()
  defp get_secrets(org_id) do
    organization = Partners.organization(org_id)

    organization.services["google_cloud_storage"]
    |> case do
      nil -> %{}
      credentials -> credentials.secrets
    end
  end

  @spec load_goth(map()) :: :ok
  defp load_goth(service_account) do
    Goth.Config.add_config(service_account)
    Goth.Config.set(:client_email, service_account["client_email"])
    Goth.Config.set("private_key", service_account["private_key"])
  end

  @doc """
  Generate a sigend url for a private file
  """
  @spec get_signed_url(String.t(), non_neg_integer, keyword) :: String.t()
  def get_signed_url(file_name, organization_id, opts \\ []) do
    Repo.put_organization_id(organization_id)
    gcs_secrets = get_secrets(organization_id)
    gcs_secrets = Map.put(gcs_secrets, "private_bucket", "test-private-cc")

    if is_nil(gcs_secrets["private_bucket"]) do
      Logger.info("no private bucket for org_id: #{organization_id}")
    else
      put_bucket_name(gcs_secrets["private_bucket"])
      load_goth(Jason.decode!(gcs_secrets["service_account"]))

      opts =
        [signed: true, expires_in: 300]
        |> Keyword.merge(opts)

      CloudStorage.url(
        Glific.Media,
        :original,
        {%Waffle.File{file_name: file_name}, "#{organization_id}"},
        opts
      )
    end
  end
end
