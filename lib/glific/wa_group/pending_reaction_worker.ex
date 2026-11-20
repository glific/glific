defmodule Glific.WAGroup.PendingReactionWorker do
  @moduledoc """
  Retries saving a Maytapi group reaction whose parent message could not be found yet.

  A reaction to a message Glific sent can only be matched once a delivery ack has stored the
  message's WhatsApp key id. The ack and the reaction webhooks are processed independently, so the
  reaction can be handled first. Each retry is scheduled as a new job after the next delay in
  `@retry_delays`; once they are used up the reaction is recorded as skipped.
  """

  use Oban.Worker,
    queue: :wa_group,
    max_attempts: 3

  alias Glific.{
    Communications.GroupMessage,
    Repo
  }

  @retry_delays [30, 120, 600]

  @doc """
  Schedules a retry of the given reaction
  """
  @spec enqueue(map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, any()}
  def enqueue(reaction_params, org_id, retry \\ 0) do
    %{reaction: reaction_params, organization_id: org_id, retry: retry}
    |> new(schedule_in: Enum.at(@retry_delays, retry))
    |> Oban.insert()
  end

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{
        args: %{"reaction" => reaction_params, "organization_id" => org_id, "retry" => retry}
      }) do
    Repo.put_process_state(org_id)

    case GroupMessage.save_reaction(reaction_params, org_id) do
      {:ok, _reaction} ->
        :ok

      {:error, :not_found} when retry + 1 < length(@retry_delays) ->
        {:ok, _job} = enqueue(reaction_params, org_id, retry + 1)
        :ok

      {:error, reason} ->
        GroupMessage.skip_reaction(reason, org_id)
    end
  end
end
