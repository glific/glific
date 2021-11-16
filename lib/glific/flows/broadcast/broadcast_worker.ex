defmodule Glific.Flows.BroadcastWorker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :broadcast,
    max_attempts: 2,
    priority: 0

  alias Glific.{Flows.Broadcast, Flows.BroadcastWorker, Repo}

  def execute(org_id)
    __MODULE__.new(%{organization_id: org_id})
    |> Oban.insert()
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id}
      }) do
    Repo.put_process_state(organization_id)
    Broadcast.execute_group_broadcasts(organization_id)
    :ok
  end
end
