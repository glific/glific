defmodule Glific.Flows.WakeupWorker do
  @moduledoc """
  Wakes up a single flow context. Jobs run in the `:flow_wakeup` queue, whose
  `global_limit` partitions by organization_id (see `config/config.exs`), so at most
  one wakeup executes at a time for a given organization while different
  organizations process in parallel.
  """

  use Oban.Worker,
    queue: :flow_wakeup,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:args, :worker],
      keys: [:organization_id],
      states: [:available, :scheduled, :executing]
    ]

  import Ecto.Query

  alias Glific.Flows.FlowContext
  alias Glific.Repo

  @wake_up_flow_limit 200

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id}
      }) do
    Repo.put_process_state(organization_id)

    FlowContext
    |> where([fc], fc.organization_id == ^organization_id)
    |> where([fc], not is_nil(fc.wakeup_at))
    |> where([fc], fc.wakeup_at < ^DateTime.utc_now())
    |> where([fc], is_nil(fc.completed_at))
    |> limit(@wake_up_flow_limit)
    |> Repo.one()
    |> case do
      nil -> :ok
      context -> context |> Repo.preload(:flow) |> FlowContext.wakeup_one()
    end

    :ok
  end
end
