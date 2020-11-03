defmodule Glific.Jobs.DailyWorker do
  @moduledoc """
  Processes the tasks that need to be handled on a minute schedule
  """

  use Oban.Worker,
    queue: :crontab,
    max_attempts: 3

  alias Glific.{
    Flows.FlowContext,
  }

  @doc """
  Worker to implement cron job functionality as implemented by Oban. This
  is a work in progress and subject to change
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) ::
          :discard | :ok | {:error, any} | {:ok, any} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"job" => "delete_flow_contexts"}} = _job) do
    FlowContext.delete_old_flow_contexts()
    :ok
  end

  def perform(_job), do: {:error, "This job is not handled"}
end
