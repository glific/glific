defmodule Glific.Flags do
  @moduledoc """
  Centralizing all the code we need to handle flags across Glific. For now, we'll
  also put operational code on flags here, as we figure out the right structure
  """

  use Publicist

  alias Glific.Partners

  @doc false
  @spec init(non_neg_integer | nil) :: {:ok, boolean()}
  def init(organization_id) do
    FunWithFlags.enable(
      :enable_out_of_office,
      for_actor: %{organization_id: organization_id}
    )

    out_of_office_update(organization_id)

    dialogflow(organization_id)
  end

  def init() do
    Partners.active_organizations()
    |> Enum.each(fn {id, _name} ->
      init(id)
    end)
  end

  @spec business_day?(DateTime.t(), [integer]) :: boolean
  defp business_day?(time, days),
    do: (time |> DateTime.to_date() |> Date.day_of_week()) in days

  @spec office_hours?(DateTime.t(), [Time.t()]) :: boolean
  defp office_hours?(time, [start_time, end_time]) do
    time = DateTime.to_time(time)
    Time.compare(time, start_time) == :gt and Time.compare(time, end_time) == :lt
  end

  defp office_hours?(_time, []), do: false

  @spec enable_out_of_office(non_neg_integer) :: nil
  defp enable_out_of_office(organization_id) do
    # enable only if needed
    if !FunWithFlags.enabled?(
         :out_of_office_active,
         for: %{organization_id: organization_id}
       ),
       do:
         FunWithFlags.enable(
           :out_of_office_active,
           for_actor: %{organization_id: organization_id}
         )
  end

  @spec disable_out_of_office(non_neg_integer) :: nil
  defp disable_out_of_office(organization_id) do
    # disable only if needed
    if FunWithFlags.enabled?(
         :out_of_office_active,
         for: %{organization_id: organization_id}
       ),
       do:
         FunWithFlags.disable(
           :out_of_office_active,
           for_actor: %{organization_id: organization_id}
         )
  end

  @spec out_of_office_check(non_neg_integer) :: nil
  defp out_of_office_check(organization_id) do
    organization = Partners.organization(organization_id)

    if organization.out_of_office.enabled do
      {:ok, now} = organization.timezone |> DateTime.now()

      hours = organization.hours
      days = organization.days

      # check if current day and time is valid
      open? = business_day?(now, days) and office_hours?(now, hours)

      if open?,
        # we are operating now, so ensure out_of_office flag is disabled
        do: disable_out_of_office(organization_id),
        # we are closed now, enable out_of_office flow
        else: enable_out_of_office(organization_id)
    else
      # disable all out of office checks
      FunWithFlags.disable(
        :enable_out_of_office,
        for_actor: %{organization_id: organization_id}
      )

      FunWithFlags.disable(
        :out_of_office_active,
        for_actor: %{organization_id: organization_id}
      )
    end
  end

  @doc """
  Update the out of office flag, so we know if we should actually do any work
  """
  @spec out_of_office_update(non_neg_integer) :: nil
  def out_of_office_update(organization_id),
    do:
      if(
        FunWithFlags.enabled?(
          :enable_out_of_office,
          for: %{organization_id: organization_id}
        ),
        do: out_of_office_check(organization_id),
        # lets make sure that out_of_office_active is disabled
        # if we dont want this functionality
        else: disable_out_of_office(organization_id)
      )

  @doc """
  See if we have valid dialogflow credentials, if so, enable dialogflow
  else disable it
  """
  @spec dialogflow(non_neg_integer) :: {:ok, boolean()}
  def dialogflow(organization_id),
    do:
      if(File.exists?("config/.dialogflow.credentials.json_#{organization_id}"),
        do:
          FunWithFlags.enable(
            :dialogflow,
            for_actor: %{organization_id: organization_id}
          ),
        else:
          FunWithFlags.disable(
            :dialogflow,
            for_actor: %{organization_id: organization_id}
          )
      )
end
