defmodule Glific.Jobs.GcsWorker do
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
    Jobs,
    Messages.Message,
    Messages.MessageMedia,
    Partners,
    Repo
  }

  @doc """
  This is called from the cron job on a regular schedule. we sweep the message media url  table
  and queue them up for delivery to gcs
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    organization = Partners.organization(organization_id)
    credential = organization.services["google_cloud_storage"]

    if credential do
      jobs(organization_id)
      :ok
    else
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

    data =
      MessageMedia
      |> select([m], m.id)
      |> join(:left, [m], msg in Message, as: :msg, on: m.id == msg.media_id)
      |> where([m], m.organization_id == ^organization_id and m.id > ^message_media_id)
      |> order_by([m], asc: m.id)
      |> limit(10)
      |> Repo.all()

    max_id = if is_list(data), do: List.last(data), else: message_media_id

    if !is_nil(max_id) and max_id > message_media_id do
      queue_urls(organization_id, message_media_id, max_id)
      Logger.info("Updating GCS jobs with max id:  #{max_id} for org_id: #{organization_id}")
      Jobs.update_gcs_job(%{message_media_id: max_id, organization_id: organization_id})
    end

    :ok
  end

  @spec queue_urls(non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  defp queue_urls(organization_id, min_id, max_id) do
    query =
      MessageMedia
      |> where([m], m.id > ^min_id and m.id <= ^max_id)
      |> join(:left, [m], msg in Message, as: :msg, on: m.id == msg.media_id)
      |> where([m, msg], msg.organization_id == ^organization_id)
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
    # We will download the file from internet and then upload it to gsc and then remove it.
    extension = get_media_extension(media["type"])

    file_name =
      "#{timestamp()}_C#{media["contact_id"]}_F#{media["flow_id"]}_M#{media["id"]}.#{extension}"

    path = "#{System.tmp_dir!()}/#{file_name}"

    media =
      media
      |> Map.put(:file_name, file_name)
      |> Map.put(:path, path)

    download_file_to_temp(media["url"], path, media["organization_id"])
    |> case do
      {:ok, _} ->
          upload_file_on_gcs(media)

      {:error, :timeout} ->
        {:error,
         "GCS Download timeout for org_id: #{media["organization_id"]}, media_id: #{media["id"]}"}

      {:error, error} ->
        {:discard,
         "GCS Upload failed for org_id: #{media["organization_id"]}, media_id: #{media["id"]}, error #{
           inspect(error)
         }"}
    end

    :ok
  end


  @spec get_public_link(map()) :: String.t()
  defp get_public_link(response) do
    Enum.join(["https://storage.googleapis.com", response.id], "/")
    |> String.replace("/#{response.generation}", "")
  end

  @spec upload_file_on_gcs(map()) ::
          {:ok, GoogleApi.Storage.V1.Model.Object.t()} | {:error, Tesla.Env.t()}
  defp upload_file_on_gcs(%{path: path, file_name: file_name} = media) do
    Logger.info("Uploading to GCS, org_id: #{media["organization_id"]}, file_name: #{file_name}")

    {:ok, response} = CloudStorage.put(
      Glific.Media,
      :original,
      {%Waffle.File{path: path, file_name: file_name}, bucket(media)}
    )

    get_public_link(response)
    |> update_gcs_url(media["id"])

    File.rm(path)
    :ok

    rescue
    # An exception is thrown when there is
    #
    error ->
      log_error(error, media["organization_id"])


  end

  # get the bucket name, we call our pseudo-plugin architecture
  # to allow NGOs to overwrite bucket names
  @spec bucket(map()) :: String.t()
  defp bucket(media) do
    organization = Partners.organization(media["organization_id"])

    bucket_name =
      organization.services["google_cloud_storage"]
      |> case do
        nil -> "custom_bucket_name"
        credentials -> credentials.secrets["bucket"]
      end

    # allow end users to override bucket_name
    Glific.Clients.gcs_bucket(media, bucket_name)
  end

  @spec update_gcs_url(String.t(), integer()) ::
          {:ok, MessageMedia.t()} | {:error, Ecto.Changeset.t()}
  defp update_gcs_url(gcs_url, id) do
    Repo.get(MessageMedia, id)
    |> MessageMedia.changeset(%{gcs_url: gcs_url})
    |> Repo.update()
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

  @spec download_file_to_temp(String.t(), String.t(), non_neg_integer) ::
          {:ok, String.t()} | {:error, any()}
  defp download_file_to_temp(url, path, org_id) do
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

  defp log_error(error, organization_id) do
    disable_account(error, organization_id)
    Logger.error("Error: while uploading the file on GCS. with organization id: #{organization_id}, #{error}")
    {:error, "Can not upload file to GCS"}
  end

  defp disable_account(error, organization_id),
  do: if String.contains(error, "The project to be billed is associated with a closed billing account."),
  do: Partners.disable_credential(organization_id, "google_cloud_storage")


end
