defmodule Glific.Jobs.MinuteWorker do
  @moduledoc """
  Processes the tasks that need to be handled on a minute schedule
  """

  use Oban.Worker, queue: :crontab

  @timezone "Asia/Kolkata"
  @days_of_week 1..5
  @hours_of_day 9..20

  @impl Oban.Worker
  @doc """
  Worker to implement cron job functionality as implemented by Oban. This
  is a work in progress and subject to change
  """
  @spec perform(Oban.Job.t()) :: :discard | :ok | {:error, any} | {:ok, any} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{job: :fun_with_flags}}) do
    if FunWithFlags.enabled?(:enable_out_of_office) do
      # check if current day and time is valid
      {:ok, now} = DateTime.now(@timezone)

      business_day? = (now |> DateTime.to_date() |> Date.day_of_week()) in @days_of_week
      office_hours? = (now |> DateTime.to_time() |> Map.get(:hour)) in @hours_of_day

      if business_day? and office_hours? do
        # we are operating now, so ensure out_of_office flag is disabled
        if FunWithFlags.enabled?(:out_of_office_active),
          do: FunWithFlags.disable(:out_of_office_active)
      else
        # we are closed now, enable out_of_office flow
        if !FunWithFlags.enabled?(:out_of_office_active),
          do: FunWithFlags.enable(:out_of_office_active)
      end
    end

    :ok
  end

  def perform(_job), do: :ok
end
