defmodule Glific.GCS.GcsWorker do
  @moduledoc """
  Process the  media table for each organization. Chunk number of message medias
  in groups of 128 and create a Gcs Worker Job to deliver the message media url to
  the gcs servers

  We centralize both the cron job and the worker job in one module
  """

  import Ecto.Query
  require Logger

  use Oban.Worker,
    queue: :gcs,
    max_attempts: 2,
    priority: 2

  alias Waffle.Storage.Google.CloudStorage

  alias Glific.{
    BigQuery,
    BigQuery.BigQueryWorker,
    Jobs,
    Messages,
    Messages.Message,
    Messages.MessageMedia,
    Partners,
    Repo
  }

  @provider_shortcode "google_cloud_storage"

  @doc """
  This is called from the cron job on a regular schedule. we sweep the message media url  table
  and queue them up for delivery to gcs
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    organization = Partners.organization(organization_id)
    credential = organization.services[@provider_shortcode]
    goth_token = Partners.get_goth_token(organization_id, @provider_shortcode)

    if is_nil(credential) || is_nil(goth_token) do
      :ok
    else
      jobs(organization_id)
      :ok
    end
  end

  @spec jobs(non_neg_integer) :: :ok
  defp jobs(organization_id) do
    gcs_job = Jobs.get_gcs_job(organization_id)

    message_media_id =
      if gcs_job == nil,
        do: 0,
        else: gcs_job.message_media_id

    message_media_id = message_media_id || 0

    limit = files_per_minute_count()

    data =
      MessageMedia
      |> select([m], m.id)
      |> join(:left, [m], msg in Message, as: :msg, on: m.id == msg.media_id)
      |> where([m], m.organization_id == ^organization_id and m.id > ^message_media_id)
      |> where([m, msg], msg.flow == :inbound)
      |> order_by([m], asc: m.id)
      |> limit(^limit)
      |> Repo.all()

    max_id = if is_list(data), do: List.last(data), else: message_media_id

    if !is_nil(max_id) and max_id > message_media_id do
      Logger.info(
        "GCSWORKER: Updating GCS jobs with max id:  #{max_id} , min id: #{message_media_id} for org_id: #{organization_id}"
      )

      queue_urls(organization_id, message_media_id, max_id)
      Jobs.update_gcs_job(%{message_media_id: max_id, organization_id: organization_id})
    end

    :ok
  end

  @spec files_per_minute_count() :: integer()
  defp files_per_minute_count do
    Application.fetch_env!(:glific, :gcs_file_count)
    |> Glific.parse_maybe_integer()
    |> case do
      {:ok, nil} -> 5
      {:ok, count} -> count
      _ -> 5
    end
  end

  @doc """
    Queue urls for gcs jobs.
  """
  @spec queue_urls(non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  def queue_urls(organization_id, min_id, max_id) do
    query =
      MessageMedia
      |> where([m], m.id > ^min_id and m.id <= ^max_id)
      |> join(:left, [m], msg in Message, as: :msg, on: m.id == msg.media_id)
      |> where([m, msg], msg.organization_id == ^organization_id)
      |> where([m, msg], msg.flow == :inbound)
      |> select([m, msg], [m.id, m.url, msg.type, msg.contact_id, msg.flow_id])
      |> order_by([m], [m.inserted_at, m.id])

    query
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, _acc ->
        row
        |> make_media(organization_id)
        |> make_job()
      end
    )
  end

  @spec make_media(list(), non_neg_integer) :: map()
  defp make_media(row, organization_id) do
    [id, url, type, contact_id, flow_id] = row

    Logger.info("GCSWORKER: Making media for media id: #{id}")

    %{
      url: url,
      id: id,
      type: type,
      contact_id: contact_id,
      flow_id: if(is_nil(flow_id), do: 0, else: flow_id),
      organization_id: organization_id
    }
  end

  @spec make_job(map()) :: :ok
  defp make_job(media) do
    {:ok, _} =
      __MODULE__.new(%{media: media})
      |> Oban.insert()

    :ok
  end

  @spec pad(non_neg_integer) :: String.t()
  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  # copied from mix task ecto.gen.migration
  @spec timestamp :: String.t()
  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:discard, String.t()}
  def perform(%Oban.Job{args: %{"media" => media}}) do
    Logger.info("GCSWORKER: Performing gcs media for media id: #{media["id"]}")

    Repo.put_process_state(media["organization_id"])

    # We will download the file from internet and then upload it to gsc and then remove it.
    extension = get_media_extension(media["type"])

    remote_name =
      "#{timestamp()}_C#{media["contact_id"]}_F#{media["flow_id"]}_M#{media["id"]}.#{extension}"

    local_name = "#{System.tmp_dir!()}/#{remote_name}"

    media =
      media
      |> Map.put("remote_name", remote_name)
      |> Map.put("local_name", local_name)

    Logger.info("GCSWORKER: Performing gcs media with details for media id: #{inspect(media)}")

    download_file_to_temp(media["url"], local_name, media["organization_id"])
    |> case do
      {:ok, _} ->
        uploading_to_gcs(local_name, media)
        :ok

      {:error, :timeout} ->
        error =
          "GCSWORKER: GCS Download timeout for org_id: #{media["organization_id"]}, media_id: #{media["id"]}"

        Logger.info(error)

        {:error, error}

      {:error, error} ->
        error =
          "GCSWORKER: GCS Upload failed for org_id: #{media["organization_id"]}, media_id: #{media["id"]}, error: #{inspect(error)}"

        Logger.info(error)

        {:discard, error}
    end
  end

  @spec uploading_to_gcs(String.t(), map()) :: :ok
  defp uploading_to_gcs(local_name, media) do
    upload_file_on_gcs(media)
    |> case do
      {:ok, response} ->
        get_public_link(response)
        |> update_gcs_url(media["id"])

        File.rm(local_name)

      {:error, error} ->
        handle_gcs_error(media["organization_id"], error)
    end

    :ok
  end

  @spec handle_gcs_error(non_neg_integer, map()) :: String.t()
  defp handle_gcs_error(org_id, error) do
    Jason.decode(error.body)
    |> case do
      {:ok, data} ->
        [error] = get_in(data, ["error", "errors"])

        # We will disabling GCS when billing account is disabled
        if error["reason"] == "accountDisabled" do
          Partners.disable_credential(
            org_id,
            "google_cloud_storage",
            "Billing account is disabled"
          )
        end

        error = "GCSWORKER: Error while uploading file to GCS #{inspect(error)}"
        Logger.info(error)

        error

      _ ->
        {_, stacktrace} = Process.info(self(), :current_stacktrace)

        error =
          "GCSWORKER: Error while uploading file to GCS #{inspect(error)} stacktrace: #{inspect(stacktrace)}"

        Logger.info(error)

        error
    end
  end

  @spec get_public_link(map()) :: String.t()
  defp get_public_link(response) do
    Enum.join(["https://storage.googleapis.com", response.id], "/")
    |> String.replace("/#{response.generation}", "")
  end

  @spec upload_file_on_gcs(map()) ::
          {:ok, GoogleApi.Storage.V1.Model.Object.t()} | {:error, Tesla.Env.t()}
  defp upload_file_on_gcs(%{"local_name" => local_name} = media) do
    remote_name = Glific.Clients.gcs_file_name(media)
    upload_file_on_gcs(local_name, remote_name, media["organization_id"])
  end

  @spec upload_file_on_gcs(String.t(), String.t(), non_neg_integer) ::
          {:ok, GoogleApi.Storage.V1.Model.Object.t()} | {:error, Tesla.Env.t()} | {:error, map()}
  defp upload_file_on_gcs(local, remote, organization_id) do
    Logger.info("GCSWORKER: Uploading to GCS, org_id: #{organization_id}, file_name: #{remote}")

    CloudStorage.put(
      Glific.Media,
      :original,
      {
        %Waffle.File{path: local, file_name: remote},
        "#{organization_id}"
      }
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

  @doc """
  Public interface to upload a file provided by the org at local name to gcs as remote name
  """
  @spec upload_media(String.t(), String.t(), non_neg_integer) ::
          {:ok, map()} | {:error, String.t()}
  def upload_media(local, remote, organization_id) do
    upload_file_on_gcs(local, remote, organization_id)
    |> case do
      {:ok, response} ->
        File.rm(local)
        {type, _media} = Messages.get_media_type_from_url(response.selfLink)
        {:ok, %{url: get_public_link(response), type: type}}

      {:error, error} ->
        error = handle_gcs_error(organization_id, error)
        {:error, error}
    end
  end

  @spec update_gcs_url(String.t(), integer()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  defp update_gcs_url(gcs_url, id) do
    {:ok, message_media} =
      Repo.get(MessageMedia, id)
      |> MessageMedia.changeset(%{gcs_url: gcs_url})
      |> Repo.update()

    organization_id = message_media.organization_id

    if BigQuery.is_active?(organization_id) do
      BigQueryWorker.queue_message_media_data([message_media], organization_id, %{
        action: :update,
        max_id: nil,
        last_updated_at: Timex.now()
      })
    end

    {:ok, message_media}
  end

  @spec get_media_extension(String.t()) :: String.t()
  defp get_media_extension(type) do
    %{
      image: "png",
      video: "mp4",
      audio: "mp3",
      document: "pdf"
    }
    |> Map.get(Glific.safe_string_to_atom(type), "png")
  end

  @doc """
  Download a file to the specific path. Should move this to a more generic
  helper file in glific
  """
  @spec download_file_to_temp(String.t(), String.t(), non_neg_integer) ::
          {:ok, String.t()} | {:error, any()}
  def download_file_to_temp(url, path, org_id) do
    Logger.info("GCSWORKER: Downloading file: org_id: #{org_id}, url: #{url}")

    Tesla.get(url, opts: [adapter: [recv_timeout: 10_000]])
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
end
