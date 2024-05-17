defmodule Glific.GCS do
  @moduledoc """
  Glific GCS Manager
  """

  @behaviour Waffle.Storage.Google.Token.Fetcher
  require Logger
  import Ecto.Query

  alias Glific.{
    GCS.GcsJob,
    Messages.Message,
    Messages.MessageMedia,
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
  @spec refresh_gcs_setup(non_neg_integer) :: {:ok, any} | {:error, any}
  def refresh_gcs_setup(organization_id) do
    Logger.info("refresh GCS setup for org_id: #{organization_id}")

    insert_gcs_jobs(organization_id)
  end

  @doc false
  @spec insert_gcs_jobs(non_neg_integer) :: {:ok, any} | {:error, any}
  def insert_gcs_jobs(organization_id) do
    Repo.fetch_by(GcsJob, %{organization_id: organization_id, type: "incremental"})
    |> case do
      {:ok, gcs_job} ->
        {:ok, gcs_job}

      _ ->
        %GcsJob{
          organization_id: organization_id,
          type: "incremental"
        }
        |> Repo.insert()
    end

    Repo.fetch_by(GcsJob, %{organization_id: organization_id, type: "unsynced"})
    |> case do
      {:ok, gcs_job} ->
        {:ok, gcs_job}

      _ ->
        message_media_id = get_first_unsynced_file(organization_id)

        %GcsJob{
          organization_id: organization_id,
          type: "unsynced",
          message_media_id: message_media_id
        }
        |> Repo.insert()
    end
  end

  @gcs_bucket_key {__MODULE__, :bucket_id}

  @doc """
  Get first unsynced file id as a starting point to sync unsynced files
  """
  @spec get_first_unsynced_file(non_neg_integer) :: non_neg_integer()
  def get_first_unsynced_file(organization_id) do
    base_query(organization_id)
    |> unsynced_query()
    |> where([m, _msg], is_nil(m.gcs_url))
    |> Repo.all()
    |> do_get_first_unsynced_file(organization_id)
  end

  # Check if ID is returned else get ID of first inbound media file
  @spec do_get_first_unsynced_file(any(), non_neg_integer) :: non_neg_integer()
  defp do_get_first_unsynced_file(media_id, organization_id) when media_id in ["", nil, []] do
    [%{id: id}] = base_query(organization_id) |> unsynced_query() |> Repo.all()

    id
  end

  defp do_get_first_unsynced_file(%{id: id}, _organization_id), do: id

  @doc """
  Check if ID is returned else get ID of first inbound media file
  """
  @spec base_query(non_neg_integer) :: Ecto.Queryable.t()
  def base_query(organization_id) do
    MessageMedia
    |> join(:left, [m], msg in Message, as: :msg, on: m.id == msg.media_id)
    |> where([m, _msg], m.organization_id == ^organization_id)
    |> where([m, _msg], m.flow == :inbound)
    |> order_by([m], [m.inserted_at, m.id])
  end

  @spec unsynced_query(Ecto.Queryable.t()) :: Ecto.Queryable.t()
  defp unsynced_query(query), do: query |> limit(1) |> select([m], %{id: m.id})

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
  Generate a signed URL for a private file
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
