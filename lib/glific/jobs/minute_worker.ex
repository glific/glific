defmodule Glific.Jobs.MinuteWorker do
  @moduledoc """
  Processes the tasks that need to be handled on a minute schedule
  """

  use Oban.Worker,
    queue: :crontab,
    max_attempts: 3

  alias Glific.{
    Contacts,
    Flags,
    Flows.FlowContext,
    Jobs.BigQueryWorker,
    Jobs.ChatbaseWorker,
    Jobs.GcsWorker,
    Partners
  }

  @doc """
  Worker to implement cron job functionality as implemented by Oban. This
  is a work in progress and subject to change
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) ::
          :discard | :ok | {:error, any} | {:ok, any} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"job" => "fun_with_flags"}} = _job) do
    Partners.perform_all(&Flags.out_of_office_update/1, nil)
    :ok
  end

  def perform(%Oban.Job{args: %{"job" => "contact_status"} = args} = _job) do
    Partners.perform_all(&Contacts.update_contact_status/2, args)
  end

  def perform(%Oban.Job{args: %{"job" => "wakeup_flows"}} = _job) do
    FlowContext.wakeup()
  end

  def perform(%Oban.Job{args: %{"job" => "chatbase"}} = _job) do
    Partners.perform_all(&ChatbaseWorker.perform_periodic/1, nil)
    :ok
  end

  def perform(%Oban.Job{args: %{"job" => "bigquery"}} = _job) do
    Partners.perform_all(&BigQueryWorker.perform_periodic/1, nil)
    :ok
  end

  def perform(%Oban.Job{args: %{"job" => "gcs"}} = _job) do
    Partners.perform_all(&GcsWorker.perform_periodic/1, nil)
    :ok
  end

  def perform(_job), do: {:error, "This job is not handled"}
end
