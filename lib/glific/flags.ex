defmodule Glific.Flags do
  @moduledoc """
  Centralizing all the code we need to handle flags across Glific. For now, we'll
  also put operational code on flags here, as we figure out the right structure
  """

  @timezone "Asia/Kolkata"
  @days_of_week 1..5 # mon .. fri
  @hours_of_day 9..18 # 9:00 - 18:59

  @spec init :: nil
  def init do
    FunWithFlags.enable(:enable_out_of_office)

    out_of_office_update()
  end

  defp business_day?(time),
    do:
  (time |> DateTime.to_date() |> Date.day_of_week() ) in @days_of_week

  defp office_hours?(time),
    do:
      (time |> DateTime.to_time() |> Map.get(:hour)) in @hours_of_day

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
    # check if current day and time is valid
    {:ok, now} = DateTime.now(@timezone)
    open? = business_day?(now) and office_hours?(now)

    if open?,
      # we are operating now, so ensure out_of_office flag is disabled
      do: disable_out_of_office(),
      # we are closed now, enable out_of_office flow
      else: enable_out_of_office()
  end

  def out_of_office_update,
    do:
      if(FunWithFlags.enabled?(:enable_out_of_office),
        do: out_of_office_check(),
        # lets make sure that out_of_office_active is disabled
        # if we dont want this functionality
        else: disable_out_of_office()
      )
end
