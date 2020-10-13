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
    config = %{
      "type" => "service_account",
      "project_id" => "beginner-290513",
      "private_key_id" => "b17c9ebd2e095a7d9d08e58341a012c8344fac6e",
      "private_key" => "-----BEGIN PRIVATE KEY-----\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCpJw8qkBVijhfY\nYBB5RL0HCydrpNw0NoQmRXkDPPiiyWWLPvP37rGizXOYoc7FEtjwblAVmPrbFDZH\nN+kf8ORCrsLirm/xVI1HiQPtN1yXjGn9fUAOjw+wMhTRXodnM1H3xczc1czxtKlM\nsXmy/rjYofVxDesU3kdszCMhXbFPWXmi9T1kEt1R2xWgPl5rsyTnNAWqwpJUo9aM\nwmleH74UwPh2wl2j+su5nXEZwn/s2wbYToId12MHfiPIRysEzQRK9CBClk/UzoQT\nDM/OUZe11D9AxVUpOixs9I9eEYVaYipIdIIMJhHD2DQJzHkYMkv26AiYo9F1/+63\nwIrXWH43AgMBAAECggEAEQsZy29qbYcPqVeUkVjMYFykA4Pq7r/cyiu507UIVa6h\nMp83NHCyfqA2LizaM/Uq3UmK0YJGfwh8Uj9fQpP3toL7/pxriboROiH4vqVos5m2\n8Y712Kxa0lAEKkxcrENO1lOcdAEpfePMIylxWl2xVkfgqRwpPEML7fnA7b24/dub\nIN1uFfbou+2taS00wbIeTg2MapxeqsjE6s+fnOVoMDjonriralBphj57mDylFxCK\n49YfpHxBS1LnTIEJpW6SG2QuLoyfMZXCO555GeDv2FnUbijwA4M5Hk4XYfJhM1Bz\nVRE/AUJCn5v1yME2sB/bb0woqi5bWS4QiyZcb1q+QQKBgQDtJQM+s8x+shYAG5vj\nx7CAKkMYA3JDUn5Pj4S1jLP12+QAlowJkOFmgIExZqTDtpuxxzd+j/KKWYXLPasF\n98JBg6b9+fWKHrqIYgzzuD3d7rY93QhqK/271G2L2ln42aOPa5W7gtnyZ+YOdvdD\n6RyEh4Uv6+Ai7xiYnZdp+JCGkQKBgQC2mhhj7FPBobfZ1WDIRYLPvQY7klktAKtd\n9nlw26Rkuy98ek4TPeFXu2xZsr66Lm4xJxIs1PKAWxoGOHW045PPzl8wznNsYY1V\nwuismCf5NFpgS3e5AyiQ5SoImsfJfACkG7rfj6HUskyNV21N8Zpvdr30DtWcZr+s\nlgDTUZ5sRwKBgAWlE+ayMPPzGUL3ZUaOwkzKtL4lltqzY/5Q1D/eEYqQqWS6MKsp\nn7Po6ypZ3yIpfptEurVwh71zVBP6a8/AjgcxMxBomsem45nLe7Nxd0eJHx1p3YFp\neqi17cWedPXPeG05il7kRnvWrUs62bfsHJmrACib3MH4HwXC+o+zMv2BAoGAIra6\nykxEQ/xlgkEBbDFiw/FwfOS+lUKaUXuo7J6k6w124pgxvZC3BUG5QHgtsCFhi3Cd\nEO7Oxz4KfYJARko5cHkQOawV31XQU6yBJUar2sFsKQBP21lRXfJjAk3Ci3hKeuhW\np2eb4V6gFQK44ed7b5NIW1xymZAjAkFmGMZccsMCgYB8jq62Cbqk/Vig7UyMYzDo\nZaPcOz2XfNLrgLbVo49Cz77/D8fmQ42zsihpsUCmiczANtdVGIOG0NZw549eJEeQ\nja5uVBg1L6g+irzg4W/L+wy/94yQtQxgf6JHLqFGO8ryfDwye4Rr1tN370uylOzG\nw2/+BufBs/Y4Tqxxy3VInA==\n-----END PRIVATE KEY-----\n",
      "client_email" => "bqglific@beginner-290513.iam.gserviceaccount.com",
      "client_id" => "104189268297059908552",
      "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
      "token_uri" => "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url" => "https://www.googleapis.com/robot/v1/metadata/x509/bqglific%40beginner-290513.iam.gserviceaccount.com"
    }
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
