defmodule Glific.Jobs.GcsWorker do
  @moduledoc """
  Process the  media table for each organization. Chunk number of message medias
  in groups of 128 and create a Gcs Worker Job to deliver the message to
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
    Messages.MessageMedia,
    Partners,
    Repo
  }

  @spec perform_periodic(non_neg_integer) :: :ok
  @doc """
  This is called from the cron job on a regular schedule. we sweep the messages table
  and queue them up for delivery to gcs
  """
  def perform_periodic(organization_id) do
    gcs_job = Jobs.get_gcs_job(organization_id)

    message_media_id =
      if gcs_job == nil,
        do: 0,
        else: gcs_job.message_media_id

    query =
      MessageMedia
      |> select([m], max(m.id))

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
      |> select([m], [m.id, m.url, m.inserted_at])
      |> order_by([m], [m.inserted_at, m.id])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        [_id, url, inserted_at] = row

        [
          %{
            url: url
          }
          | acc
        ]
      end
    )
    |> Enum.chunk_every(1)
    |> Enum.each(&make_job(&1, organization_id))
  end

  defp make_job(urls, organization_id) do
    __MODULE__.new(%{organization_id: organization_id, urls: urls})
    |> Oban.insert()
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(%Oban.Job{args: %{"urls" => urls, "organization_id" => organization_id}}) do
    # we'll get the gcs key from here
    CloudStorage.put(Glific.Media, :original, {%Waffle.File{path: Path.expand("~/Downloads/hello.png", __DIR__), file_name: "te.png"}, "1"})
    :ok
  end
end
