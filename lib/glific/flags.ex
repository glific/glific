defmodule Glific.Flags do
  @moduledoc """
  Centralizing all the code we need to handle flags across Glific. For now, we'll
  also put operational code on flags here, as we figure out the right structure
  """

  alias Glific.Partners

  @doc false
  @spec init :: {:ok, boolean()}
  def init do
    FunWithFlags.enable(:enable_out_of_office)

    out_of_office_update()

    dialogflow()
  end

  defp business_day?(time, days),
    do: (time |> DateTime.to_date() |> Date.day_of_week()) in days

  defp office_hours?(time, [start_time, end_time]) do
    time = DateTime.to_time(time)
    Time.compare(time, start_time) == :gt and Time.compare(time, end_time) == :lt
  end

  defp enable_out_of_office do
    # enable only if needed
    if !FunWithFlags.enabled?(:out_of_office_active),
      do: FunWithFlags.enable(:out_of_office_active)
  end

  defp disable_out_of_office do
    # disable only if needed
    if FunWithFlags.enabled?(:out_of_office_active),
      do: FunWithFlags.disable(:out_of_office_active)
  end

  defp out_of_office_check do
    timezone = Partners.organization_timezone()

    {:ok, now} = DateTime.now(timezone)

    {hours, days} = Partners.organization_out_of_office_summary()

    # check if current day and time is valid
    open? = business_day?(now, days) and office_hours?(now, hours)

    if open?,
      # we are operating now, so ensure out_of_office flag is disabled
      do: disable_out_of_office(),
      # we are closed now, enable out_of_office flow
      else: enable_out_of_office()
  end

  @doc """
  Update the out of office flag, so we know if we should actually do any work
  """
  @spec out_of_office_update() :: nil
  def out_of_office_update,
    do:
      if(FunWithFlags.enabled?(:enable_out_of_office),
        do: out_of_office_check(),
        # lets make sure that out_of_office_active is disabled
        # if we dont want this functionality
        else: disable_out_of_office()
      )

  @doc """
  See if we have valid dialogflow credentials, if so, enable dialogflow
  else disable it
  """
  @spec dialogflow() :: {:ok, boolean()}
  def dialogflow,
    do:
      if(File.exists?("config/.dialogflow.credentials.json"),
        do: FunWithFlags.enable(:dialogflow),
        else: FunWithFlags.disable(:dialogflow)
      )
end
