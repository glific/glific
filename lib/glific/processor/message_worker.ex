defmodule Glific.Processor.MessageWorker do
  @moduledoc """
  Oban worker that runs a single inbound message through the tagger and the flow
  engine, on the `gupshup_inbound` queue.

  Replaces the former poolboy `:message_pool` + `ConsumerWorker` GenServer
  pipeline: the queue's global limit is partitioned by organization, so a
  traffic surge from one org queues behind its own allowance instead of
  exhausting the shared pool for every other org.
  """

  use Oban.Worker,
    queue: :gupshup_inbound,
    max_attempts: 1

  use Publicist

  alias Glific.{
    Flows.Node,
    Messages.Message,
    Processor.ConsumerFlow,
    Processor.ConsumerTagger,
    Repo
  }

  @doc """
  Enqueue an inbound message for tagging and flow processing.
  """
  @spec make_job(Message.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def make_job(message) do
    %{message_id: message.id, organization_id: message.organization_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"message_id" => message_id, "organization_id" => organization_id}
      }) do
    Repo.put_process_state(organization_id)
    Node.reset_node_map()

    Message
    |> Repo.get!(message_id)
    |> process_message(load_state(organization_id))

    :ok
  end

  @spec load_state(non_neg_integer()) :: map()
  defp load_state(organization_id) do
    %{organization_id: organization_id}
    |> Map.merge(ConsumerTagger.load_state(organization_id))
    |> Map.merge(ConsumerFlow.load_state(organization_id))
  end

  # chained flows can legitimately take a while (a measured 4-flow chain took ~11s,
  # and the old genserver budget was 20s), but a runaway flow should not hold a
  # queue slot forever
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(1)

  @spec process_message(Message.t(), map()) :: Message.t()
  defp process_message(message, state) do
    body = Glific.string_clean(message.body)

    message =
      Repo.preload(message, [:location, :media, :whatsapp_form_response, contact: [:language]])

    {message, state}
    |> ConsumerTagger.process_message(body)
    |> ConsumerFlow.process_message(body)
    |> elem(0)
  end
end
