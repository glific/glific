defmodule Glific.WAGroup.PendingReactionWorker do
  @moduledoc """
  Retries saving a Maytapi group reaction whose parent message could not be found yet.

  The reaction and the message it refers to arrive as separate webhooks that are processed
  independently, so a reaction can be handled before its parent message is stored. Each retry is
  scheduled as a new job after the next delay in `@retry_delays`; once they are used up the
  reaction is recorded as skipped.

  A reactor has at most one pending job per parent message, and a newer event replaces the args of
  the waiting job, so only the reactor's latest reaction (or removal) is retried. A reaction that
  is saved directly cancels that pending job, so an older queued event cannot overwrite it.
  """

  use Oban.Worker,
    queue: :wa_group,
    max_attempts: 3,
    # executing is left out so a running job can schedule its own next retry
    unique: [
      keys: [:parent_msg_id, :reactor_id, :organization_id],
      states: [:available, :scheduled],
      period: :infinity
    ]

  import Ecto.Query

  alias Glific.{
    Communications.GroupMessage,
    Repo
  }

  @retry_delays [30, 120, 600]

  @doc """
  Schedules a retry of the given reaction, replacing any reaction from the same reactor still waiting
  """
  @spec enqueue(map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Oban.Job.t()} | {:error, any()}
  def enqueue(reaction_params, org_id, retry \\ 0) do
    reaction_params
    |> pending_key(org_id)
    |> Map.merge(%{reaction: reaction_params, retry: retry})
    |> new(schedule_in: Enum.at(@retry_delays, retry), replace: replace_waiting(retry))
    |> Oban.insert()
  end

  # a new event is newer than the one waiting, but a retry step is older than any event that
  # arrived while it ran, so only a new event may overwrite the waiting args
  @spec replace_waiting(non_neg_integer()) :: keyword()
  defp replace_waiting(0), do: [scheduled: [:args], available: [:args]]
  defp replace_waiting(_retry), do: []

  @doc """
  Cancels the retry waiting for the same reactor and parent message, if there is one
  """
  @spec cancel_pending(map(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def cancel_pending(reaction_params, org_id) do
    worker = Oban.Worker.to_string(__MODULE__)
    key = pending_key(reaction_params, org_id)

    from(job in Oban.Job,
      where:
        job.worker == ^worker and job.state in ["available", "scheduled"] and
          fragment("? @> ?", job.args, type(^key, :map))
    )
    |> Oban.cancel_all_jobs()
  end

  @spec pending_key(map(), non_neg_integer()) :: map()
  defp pending_key(reaction_params, org_id) do
    %{
      parent_msg_id: reaction_params["msgId"],
      reactor_id: reaction_params["reactorId"],
      organization_id: org_id
    }
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
