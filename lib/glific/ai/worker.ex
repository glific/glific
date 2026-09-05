defmodule Glific.AI.Worker do
  @moduledoc """
  Runs a Glific AI message in the background.

  `max_attempts: 1`: a retry would call the model again, costing money twice and
  possibly answering differently. `req_llm` already retries the HTTP call for
  transient failures, and a failure is recorded on the message.
  """

  use Oban.Worker, queue: :glific_ai, max_attempts: 1

  alias Glific.{AI.Agent, AI.Message, Repo, Users.User}

  @doc "Queues a request to run."
  @spec enqueue(Message.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(%Message{} = message) do
    %{message_id: message.id, organization_id: message.organization_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"message_id" => message_id, "organization_id" => org_id}}) do
    Repo.put_organization_id(org_id)

    message = Repo.get!(Message, message_id)
    user = Repo.get!(User, message.user_id)
    Repo.put_current_user(user)

    case Agent.run(message, user) do
      {:ok, _answer, _meta} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
