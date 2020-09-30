defmodule Glific.Jobs.ChatbaseWorker do
  @moduledoc """
  Process the message table for each organization. Chunk number of messages
  in groups of 128 and create a Chatbase Worker Job to deliver the message to
  the chatbase servers

  We centralize both the cron job and the worker job in one module
  """

  import Ecto.Query

  use Oban.Worker,
    queue: :chatbase,
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
  and queue them up for delivery to chatbase
  """
  def perform_periodic(organization_id) do
    chatbase_job = Jobs.get_chatbase_job!(organization_id)
    message_id = chatbase_job.message_id

    query =
      Message
      |> select([m], [m.id, m.body, m.flow, m.inserted_at, m.contact_id])
      |> where([m], m.organization_id == ^organization_id)

    query =
      if message_id != nil,
        do: query |> where([m], m.message_id > ^message_id),
        else: query

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        [_id, body, flow, inserted_at, contact_id] = row

        [
          %{
            type: if(flow == :inbound, do: :user, else: :agent),
            platform: "WhatsApp",
            user_id: contact_id,
            message: body,
            time_stamp: DateTime.to_unix(inserted_at)
          }
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, organization_id))
  end

  defp make_job(messages, organization_id) do
    __MODULE__.new(%{organization_id: organization_id, messages: messages})
    |> Oban.insert()
  end

  @chatbase_url "https://chatbase.com/api/messages"

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(%Oban.Job{args: %{"messages" => messages, "organization_id" => organization_id}}) do
    organization = Partners.organization(organization_id)

    if organization.services.chatbase do
      api_key = organization.services.chatbase.api_key
      messages = Enum.map(messages, fn m -> Map.put(m, "api_key", api_key) end)
      data = %{"messages" => messages}

      case Tesla.post(@chatbase_url, Poison.encode!(data)) do
        {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
          :ok

        _ ->
          {:error, "Chatbase returned an unexpected result"}
      end
    else
      :ok
    end
  end
end
