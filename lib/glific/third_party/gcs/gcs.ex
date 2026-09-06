defmodule Glific.GCS do
  @moduledoc """
  Glific GCS Manager
  """

  @behaviour Waffle.Storage.Google.Token.Fetcher
  require Logger
  import Ecto.Query

  alias Glific.{
    Communications.Mailer,
    GCS.GcsJob,
    GCS.SignedUrl,
    Mails.MediaSyncMail,
    Messages.Message,
    Messages.MessageMedia,
    Partners,
    Partners.Credential,
    Partners.Organization,
    Partners.Saas,
    Repo,
    RepoReplica
  }

  @endpoint "https://storage.googleapis.com/storage/v1/b"

  # Distinctive marker stored in message_media.gcs_error for a *permanent* provider
  # failure (invalid/expired media id). base_query/1 skips only rows whose gcs_error
  # matches this — other (transient) errors are recorded on the row for visibility
  # but stay eligible for retry. Kept as a shared constant so the writer (GcsWorker)
  # and the reader (base_query) can never drift apart.
  @invalid_media_error "Invalid/expired media id on provider"

  @doc """
  The gcs_error marker used to permanently skip media the provider no longer has.
  """
  @spec invalid_media_error() :: String.t()
  def invalid_media_error, do: @invalid_media_error

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
    RepoReplica.fetch_by(GcsJob, %{organization_id: organization_id, type: "incremental"})
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

    RepoReplica.fetch_by(GcsJob, %{organization_id: organization_id, type: "unsynced"})
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
    |> RepoReplica.all()
    |> do_get_first_unsynced_file(organization_id)
  end

  # Check if ID is returned else get ID of first inbound media file
  @spec do_get_first_unsynced_file(any(), non_neg_integer) :: non_neg_integer() | nil
  defp do_get_first_unsynced_file(media_id, organization_id) when media_id in ["", nil, []] do
    base_query(organization_id)
    |> unsynced_query()
    |> RepoReplica.all()
    |> case do
      [] -> nil
      [%{id: id}] -> id
    end
  end

  defp do_get_first_unsynced_file([%{id: id}], _organization_id), do: id

  @doc """
  Check if ID is returned else get ID of first inbound media file
  """
  @spec base_query(non_neg_integer) :: Ecto.Queryable.t()
  def base_query(organization_id) do
    MessageMedia
    |> join(:left, [m], msg in Message, as: :msg, on: m.id == msg.media_id)
    |> where([m, _msg], m.organization_id == ^organization_id)
    |> where([m, _msg], m.flow == :inbound)
    # Meta/Gupshup expire media after 7 days, so anything older is already gone on
    |> where([m], m.inserted_at > fragment("NOW() - INTERVAL '7 day'"))
    # Skip only media that permanently failed on the provider (invalid/expired media
    # id), matched by the gcs_error marker. Transient errors are still recorded on the
    # row for visibility but remain eligible for retry. coalesce/2 maps a NULL gcs_error
    # (the healthy, not-yet-synced case) to "" so it never matches and stays eligible.
    |> where([m, _msg], not ilike(coalesce(m.gcs_error, ^""), ^"%#{@invalid_media_error}%"))
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

  @doc """
  The organization's raw `google_cloud_storage` credential secrets (`"bucket"`,
  `"service_account"`, ...), or `%{}` if GCS isn't configured for it.
  """
  @spec get_secrets(non_neg_integer()) :: map()
  def get_secrets(org_id) do
    organization = Partners.organization(org_id)

    organization.services["google_cloud_storage"]
    |> case do
      nil -> %{}
      credentials -> credentials.secrets
    end
  end

  @doc """
  A short-lived signed GET URL for a private file, valid for `opts[:expires_in]` seconds
  (default 300).

  Signs directly through `GCS.SignedUrl`, passing the organization's own service-account
  credential as an argument, rather than through waffle's signer — that path (and the
  `load_goth/1` this replaced) stashed the credential in `Goth.Config`'s single shared
  `:default` slot, so two organizations signing around the same time could sign with each
  other's identity.
  """
  @spec get_signed_url(String.t(), non_neg_integer, keyword) ::
          {:ok, String.t()} | {:error, :no_private_bucket | :gcs_not_configured | :signing_failed}
  def get_signed_url(file_name, organization_id, opts \\ []) do
    Repo.put_organization_id(organization_id)

    case get_secrets(organization_id)["private_bucket"] do
      nil ->
        Logger.info("no private bucket for org_id: #{organization_id}")
        {:error, :no_private_bucket}

      private_bucket ->
        expires_in = Keyword.get(opts, :expires_in, 300)
        SignedUrl.signed_get_url(organization_id, private_bucket, file_name, expires_in)
    end
  end

  @doc """
  The GCS bucket name configured for `org_id`, or `nil` if GCS isn't configured for it.
  """
  @spec bucket_name(non_neg_integer()) :: String.t() | nil
  def bucket_name(org_id) do
    case get_secrets(org_id) do
      %{"bucket" => bucket} -> bucket
      _ -> nil
    end
  end

  @doc """
  Enabling bucket logging for the specified organization
  """
  @spec enable_bucket_logs(non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def enable_bucket_logs(org_id) do
    case bucket_name(org_id) do
      nil ->
        Logger.error("Bucket name not found for organization ID: #{org_id}")
        {:error, "Bucket name not found"}

      bucket_name ->
        log_bucket = "#{bucket_name}-logs"
        log_object_prefix = "log_object_prefix"

        case do_enable_bucket_logs(bucket_name, log_bucket, log_object_prefix) do
          {:ok, _result} ->
            Logger.info("Bucket logging enabled successfully for bucket: #{bucket_name}")
            {:ok, "Bucket logging enabled successfully"}

          {:error, error} ->
            Logger.error(
              "Failed to enable bucket logging for bucket: #{bucket_name}. Error: #{Glific.SafeLog.safe_inspect(error)}"
            )

            {:error, error}
        end
    end
  end

  @doc """
  Sending a weekly gcs media sync report

  We take the data from the last week.
  """
  @spec send_internal_media_sync_report :: :ok
  def send_internal_media_sync_report do
    media_sync_data = generate_media_sync_data()

    with {:error, err} <-
           MediaSyncMail.new_mail(media_sync_data)
           |> Mailer.send(%{
             category: "media_sync_report",
             organization_id: Saas.organization_id()
           }) do
      Logger.error(
        "Sending gcs media sync report failed due to #{Glific.SafeLog.safe_inspect(err)}"
      )
    end

    :ok
  end

  @spec do_enable_bucket_logs(String.t(), String.t(), String.t()) ::
          {:ok, any()} | {:error, any()}
  defp do_enable_bucket_logs(bucket_name, log_bucket, log_object_prefix) do
    url = "#{@endpoint}/#{bucket_name}"

    body = %{
      "logging" => %{
        "logBucket" => log_bucket,
        "logObjectPrefix" => log_object_prefix
      }
    }

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Content-Type", "application/json"}]}
    ]

    client = Tesla.client(middleware)

    case Tesla.patch(client, url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status_code, body: response_body}} ->
        {:error, %{status_code: status_code, body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec generate_media_sync_data :: list(map())
  defp generate_media_sync_data do
    get_active_gcs_orgs =
      Credential
      |> where([c], c.provider_id == 6 and c.is_active == true)
      |> select([c], c.organization_id)

    MessageMedia
    |> join(:left, [m], orgs in Organization, as: :orgs, on: m.organization_id == orgs.id)
    |> where([m, _orgs], m.inserted_at >= fragment("NOW() - INTERVAL '14 day'"))
    |> where([m, _orgs], m.inserted_at <= fragment("NOW()"))
    |> where([m, orgs], m.organization_id in subquery(get_active_gcs_orgs))
    |> select([m, orgs], %{
      name: orgs.name,
      organization_id: m.organization_id,
      all_files: fragment("COUNT(CASE WHEN ? = 'inbound' THEN 1 END)", m.flow),
      unsynced_files:
        selected_as(
          fragment("COUNT(CASE WHEN ? = 'inbound' AND ? IS NULL THEN 1 END)", m.flow, m.gcs_url),
          :unsynced
        )
    })
    |> group_by([m, orgs], [m.organization_id, orgs.name])
    |> order_by([_, _], desc: selected_as(:unsynced))
    |> limit(50)
    |> Repo.all(skip_organization_id: true)
  end
end
