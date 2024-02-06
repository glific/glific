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
    FunWithFlags.enable(
      :enable_out_of_office,
      for_actor: %{organization_id: organization.id}
    )

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
    get_out_of_office(Partners.organization(organization))
  end

  def out_of_office_update(organization), do: get_out_of_office(organization)

  @doc """
  Check the out of office flag and enable/disable based on it
  """
  @spec get_out_of_office(Organization.t()) :: nil
  def get_out_of_office(organization) do
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

  @doc """
  Get show uuid on nodes value for organization flag
  """
  @spec get_flow_uuid_display(map()) :: boolean
  def get_flow_uuid_display(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:flow_uuid_display, for: %{organization_id: organization.id}) ->
        true

      trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  # the below 2 conditions are just for testing and prototyping purposes
  # we'll get rid of them when we start using this actively
  @spec trusted_env?(atom(), non_neg_integer()) :: boolean
  defp trusted_env?(:dev, 1), do: true
  defp trusted_env?(:prod, 2), do: true
  defp trusted_env?(_env, _id), do: false

  @doc """
  Get role and permission value for organization flag
  """
  @spec get_roles_and_permission(Organization.t()) :: boolean()
  def get_roles_and_permission(organization),
    do: FunWithFlags.enabled?(:roles_and_permission, for: %{organization_id: organization.id})

  @doc """
  Get ticketing value for organization flag
  """
  @spec get_ticketing_enabled(map()) :: boolean
  def get_ticketing_enabled(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_ticketing_enabled, for: %{organization_id: organization.id}) ->
        true

      trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get auto translation via openAI value for organization flag
  """
  @spec get_auto_translation_enabled_for_open_ai(map()) :: boolean
  def get_auto_translation_enabled_for_open_ai(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_auto_translation_enabled_for_open_ai,
        for: %{organization_id: organization.id}
      ) ->
        true

      trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get google translation value for organization flag
  """
  @spec get_auto_translation_enabled_for_google_trans(map()) :: boolean
  def get_auto_translation_enabled_for_google_trans(organization) do
    FunWithFlags.enabled?(:is_auto_translation_enabled_for_google_trans, for: %{organization_id: organization.id})
  end

  @doc """
  Get contact profile value for organization flag
  """
  @spec get_contact_profile_enabled(map()) :: boolean
  def get_contact_profile_enabled(organization),
    do:
      FunWithFlags.enabled?(:is_contact_profile_enabled, for: %{organization_id: organization.id})

  @doc """
  Set fun_with_flag toggle for ticketing for an organization
  """
  @spec set_ticketing_enabled(map()) :: map()
  def set_ticketing_enabled(organization) do
    Map.put(
      organization,
      :is_ticketing_enabled,
      get_ticketing_enabled(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for auto translation for an organization
  """
  @spec set_auto_translation_enabled_for_open_ai(map()) :: map()
  def set_auto_translation_enabled_for_open_ai(organization) do
    Map.put(
      organization,
      :is_auto_translation_enabled_for_open_ai,
      get_auto_translation_enabled_for_open_ai(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for google translation for an organization
  """
  @spec set_auto_translation_enabled_for_google_trans(map()) :: map()
  def set_auto_translation_enabled_for_google_trans(organization) do
    Map.put(
      organization,
      :is_auto_translation_enabled_for_google_trans,
      get_auto_translation_enabled_for_google_trans(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for out of office for an organization
  """
  @spec set_out_of_office(map()) :: map()
  def set_out_of_office(organization) do
    Map.put(
      organization,
      :enable_out_of_office,
      get_out_of_office(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for uuid on nodes for an organization
  """
  @spec set_flow_uuid_display(map()) :: map()
  def set_flow_uuid_display(organization) do
    Map.put(
      organization,
      :is_flow_uuid_display,
      get_flow_uuid_display(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for roles and permission for an organization
  """
  @spec set_roles_and_permission(map()) :: map()
  def set_roles_and_permission(organization) do
    Map.put(
      organization,
      :is_roles_and_permission,
      get_roles_and_permission(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for contact profile enabled for an organization
  """
  @spec set_contact_profile_enabled(map()) :: map()
  def set_contact_profile_enabled(organization) do
    Map.put(
      organization,
      :is_contact_profile_enabled,
      get_contact_profile_enabled(organization)
    )
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
      :is_ticketing_enabled,
      :is_auto_translation_enabled_for_open_ai,
      :is_auto_translation_enabled_for_google_trans
    ]
    |> Enum.each(fn flag ->
      if !FunWithFlags.enabled?(
           flag,
           for: %{organization_id: organization.id}
         ),
         do:
           FunWithFlags.disable(
             flag,
             for_actor: %{organization_id: organization.id}
           )
    end)
  end
end
