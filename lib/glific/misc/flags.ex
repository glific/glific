defmodule Glific.Flags do
  @moduledoc """
  Centralizing all the code we need to handle flags across Glific. For now, we'll
  also put operational code on flags here, as we figure out the right structure
  """

  use Publicist

  alias Glific.{
    Partners,
    Partners.Organization
  }

  @doc false
  @spec init(Organization.t()) :: nil
  def init(organization) do
    init_fun_with_flags(organization)
    out_of_office_update(organization)

    dialogflow(organization)
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

  @spec out_of_office_check(Organization.t()) :: nil
  defp out_of_office_check(organization) do
    if organization.out_of_office.enabled do
      {:ok, now} = organization.timezone |> DateTime.now()

      hours = organization.hours
      days = organization.days

      # check if current day and time is valid
      open? = business_day?(now, days) and office_hours?(now, hours)

      if open?,
        # we are operating now, so ensure out_of_office flag is disabled
        do: disable_out_of_office(organization.id),
        # we are closed now, enable out_of_office flow
        else: enable_out_of_office(organization.id)
    else
      # disable all out of office checks
      FunWithFlags.disable(
        :enable_out_of_office,
        for_actor: %{organization_id: organization.id}
      )

      FunWithFlags.disable(
        :out_of_office_active,
        for_actor: %{organization_id: organization.id}
      )
    end
  end

  @doc """
  Update the out of office flag, so we know if we should actually do any work
  """
  @spec out_of_office_update(Organization.t() | non_neg_integer) :: nil
  def out_of_office_update(organization) when is_integer(organization) do
    out_of_office_update(Partners.organization(organization))
  end

  def out_of_office_update(organization) do
    if(
      FunWithFlags.enabled?(
        :enable_out_of_office,
        for: %{organization_id: organization.id}
      ),
      do: out_of_office_check(organization),
      # lets make sure that out_of_office_active is disabled
      # if we don't want this functionality
      else: disable_out_of_office(organization.id)
    )
  end

  @doc """
  See if we have valid dialogflow credentials, if so, enable dialogflow
  else disable it
  """
  @spec dialogflow(Organization.t()) :: nil
  def dialogflow(organization) do
    organization.services["dialogflow"]
    |> case do
      nil ->
        FunWithFlags.disable(
          :dialogflow,
          for_actor: %{organization_id: organization.id}
        )

      _credential ->
        FunWithFlags.enable(
          :dialogflow,
          for_actor: %{organization_id: organization.id}
        )
    end

    nil
  end

  # setting default fun_with_flags values as disabled for an organization except for out_of_office
  @spec init_fun_with_flags(Organization.t()) :: :ok
  defp init_fun_with_flags(organization) do
    FunWithFlags.enable(
      :enable_out_of_office,
      for_actor: %{organization_id: organization.id}
    )

    [
      :is_contact_profile_enabled,
      :flow_uuid_display,
      :roles_and_permission,
      :is_ticketing_enabled
    ]
    |> Enum.each(fn flag ->
      FunWithFlags.disable(
        flag,
        for_actor: %{organization_id: organization.id}
      )
    end)
  end
end
