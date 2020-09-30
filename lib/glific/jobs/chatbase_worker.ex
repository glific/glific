defmodule Glific.Jobs.ChatbaseWorker do
  @moduledoc """
  Process the message table for each organization. Chunk number of messages
  in groups of 128 and create a Chatbase Worker Job to deliver the message to
  the chatbase servers

  We centralize both the cron job and the worker job in one module
  """

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
  and queue them up for delivery to chatbase
  """
  def perform_periodic(organization_id) do
    chatbase_job = Jobs.get_chatbase_job(organization_id) |> IO.inspect()
    message_id =
    if chatbase_job == nil,
      do: 0,
    else: chatbase_job.message_id

    query =
      Message
      |> select([m], max(m.id))
      |> where([m], m.organization_id == ^organization_id)

    max_id = Repo.one(query) |> IO.inspect()
    if max_id > message_id do
      Jobs.upsert_chatbase_job(%{message_id: max_id, organization_id: organization_id})
      queue_messages(organization_id, message_id, max_id)
    end
    :ok

  end

  @spec queue_messages(non_neg_integer, non_neg_integer, non_neg_integer) :: nil
  defp queue_messages(organization_id, min_id, max_id) do
    query =
      Message
      |> select([m], [m.id, m.body, m.flow, m.inserted_at, m.contact_id])
      |> where([m], m.organization_id == ^organization_id)
      |> where([m], m.id > ^min_id and m.id <= ^max_id)
      |> order_by([m], [m.inserted_at, m.id])

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
    # we'll get the chatbase key from here
    _organization = Partners.organization(organization_id)

    secrets = Application.fetch_env!(:glific, :secrets)
    chatbase = Keyword.get(secrets, :chatbase)
    api_key = Keyword.get(chatbase, :api_key)
    if api_key do
      # api_key = organization.services.chatbase.api_key
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
