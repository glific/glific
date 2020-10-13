defmodule Glific.Jobs.BigqueryWorker do
  @moduledoc """
  Process the message table for each organization. Chunk number of messages
  in groups of 128 and create a bigquery Worker Job to deliver the message to
  the bigquery servers

  We centralize both the cron job and the worker job in one module
  """

  alias __MODULE__
  import Ecto.Query

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    priority: 0

  alias Glific.{
    Jobs,
    Messages.Message,
    Partners,
    Repo
  }

  @spec perform_periodic(non_neg_integer) :: :ok
  @doc """
  This is called from the cron job on a regular schedule. we sweep the messages table
  and queue them up for delivery to bigquery
  """
  def perform_periodic(organization_id) do
    bigquery_job = Jobs.get_bigquery_job(organization_id)
    message_id =
      if bigquery_job == nil,
        do: 0,
        else: bigquery_job.message_id

    query =
      Message
      |> select([m], max(m.id))
      |> where([m], m.organization_id == ^organization_id)

    max_id = Repo.one(query)

    if max_id > message_id do
      Jobs.upsert_bigquery_job(%{message_id: max_id, organization_id: organization_id})
      queue_table_data(organization_id, message_id, max_id)
    end

    :ok
  end


  defp setup_tables(bigquery_job, organization_id) do
   ## we will setup the data here.
  end

  @spec queue_table_data(non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  defp queue_table_data(organization_id, min_id, max_id) do
    query =
      Message
      |> select([m], [m.id, m.body, m.contact_id])
      |> where([m], m.organization_id == ^organization_id)
      |> where([m], m.id > ^min_id and m.id <= ^max_id)
      |> order_by([m], [m.inserted_at, m.id])
      |> preload([:tags, :receiver, :sender, :contact])


    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        [_id, body, contact_id] = row

        [
          %{
            ID: contact_id,
            name: body
          }
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, organization_id))
  end

  defp make_job(messages, organization_id) do
    BigqueryWorker.new(%{organization_id: organization_id, messages: messages})
    |> Oban.insert()
  end

  defp token() do
    config = %{}
    Goth.Config.add_config(config)
    {:ok, token} = Goth.Token.for_scope({"bqglific@beginner-290513.iam.gserviceaccount.com", "https://www.googleapis.com/auth/cloud-platform"})
    token
  end
  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(%Oban.Job{args: %{"messages" => messages, "organization_id" => organization_id}}) do

    _organization = Partners.organization(organization_id)
    project_id = "beginner-290513"
    dataset_id = "demo"
    table_id = "work"
    token = token()
    conn = GoogleApi.BigQuery.V2.Connection.new(token.token)
    if token do
      # api_key = organization.services.bigquery.api_key
      data = %{"messages" => messages}
      {:ok, response} = GoogleApi.BigQuery.V2.Api.Tabledata.bigquery_tabledata_insert_all(
        conn,
        project_id,
        dataset_id,
        table_id,
        [body: %{
          rows: %{
            json: %{
              ID: "21",
              name: "GlificOban"
            }
          }
        }
        ],
        []
      )
      response

    else
      :ok
    end
  end
end
