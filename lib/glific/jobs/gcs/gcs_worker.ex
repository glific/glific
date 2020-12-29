defmodule Glific.Jobs.GcsWorker do
  @moduledoc """
  Process the  media table for each organization. Chunk number of message medias
  in groups of 128 and create a Gcs Worker Job to deliver the message media url to
  the gcs servers

  We centralize both the cron job and the worker job in one module
  """

  import Ecto.Query

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    priority: 0

  alias Waffle.Storage.Google.CloudStorage

  alias Glific.{
    Jobs,
    Messages.Message,
    Messages.MessageMedia,
    Partners,
    Repo
  }

  @spec perform_periodic(non_neg_integer) :: :ok
  @doc """
  This is called from the cron job on a regular schedule. we sweep the message media url  table
  and queue them up for delivery to gcs
  """
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

  defp jobs(organization_id) do
    gcs_job = Jobs.get_gcs_job(organization_id)

    message_media_id =
      if gcs_job == nil,
        do: 0,
        else: gcs_job.message_media_id

    query =
      MessageMedia
      |> select([m], max(m.id))
      |> join(:left, [m], msg in Message, as: :msg, on: m.id == msg.media_id)
      |> where([m, msg], msg.organization_id == ^organization_id)

    max_id = Repo.one(query)

    if max_id > message_media_id do
      Jobs.upsert_gcs_job(%{message_media_id: max_id, organization_id: organization_id})
      queue_urls(organization_id, message_media_id, max_id)
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
      |> select([m, msg], [m.id, m.url, msg.type, msg.contact_id])
      |> order_by([m], [m.inserted_at, m.id])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, _acc ->
        [id, url, type, contact_id] = row

        %{
          url: url,
          id: id,
          type: type,
          contact_id: contact_id
        }
        |> make_job(organization_id)
      end
    )
  end

  defp make_job(media, organization_id) do
    __MODULE__.new(%{organization_id: organization_id, media: media})
    |> Oban.insert()
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(%Oban.Job{args: %{"media" => media, "organization_id" => organization_id}}) do
    # We will download the file from internet and then upload it to gsc and then remove it.
    extension = get_media_extension(media["type"])
    file_name = "#{Ecto.UUID.generate()}_#{media["contact_id"]}.#{extension}"
    path = "#{System.tmp_dir!()}/#{file_name}"
    download_file_to_temp(media["url"], path)
    |> case do
      {:ok, _} ->
        {:ok, response} = upload_file_on_gcs(path, organization_id, file_name)

        get_public_link(response)
        |> update_gcs_url(media["id"])

        File.rm(path)
    end

    :ok
  end

  @spec get_public_link(map()) :: String.t()
  defp get_public_link(response) do
    Enum.join(["https://storage.googleapis.com", response.id], "/")
    |> String.replace("/#{response.generation}", "")
  end

  defp upload_file_on_gcs(path, org_id, file_name) do
    CloudStorage.put(
      Glific.Media,
      :original,
      {%Waffle.File{path: path, file_name: file_name}, Integer.to_string(org_id)}
    )
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
      audio: "mp3"
    }
    |> Map.get(String.to_existing_atom(type), "png")
  end

  defp download_file_to_temp(url, path) do
    %HTTPoison.Response{body: data} = HTTPoison.get!(url)
    File.write!(path, data)
    {:ok, path}
  end
end
