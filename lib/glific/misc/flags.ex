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

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

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

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get whatsapp group value for organization flag
  """
  @spec get_whatsapp_group_enabled(map()) :: boolean
  def get_whatsapp_group_enabled(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_whatsapp_group_enabled, for: %{organization_id: organization.id}) ->
        true

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get custom certificate value for organization flag
  """
  @spec get_certificate_enabled(map()) :: boolean
  def get_certificate_enabled(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_certificate_enabled,
        for: %{organization_id: organization.id}
      ) ->
        true

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get ai-platform value for organization flag
  """
  @spec get_is_kaapi_enabled(map()) :: boolean
  def get_is_kaapi_enabled(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_kaapi_enabled, for: %{organization_id: organization.id}) ->
        true

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get Interactive Message re-response value for organization flag
  """
  @spec get_interactive_re_response_enabled(map()) :: boolean
  def get_interactive_re_response_enabled(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_interactive_re_response_enabled,
        for: %{organization_id: organization.id}
      ) ->
        true

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get OpenAI auto translation value for organization flag
  """
  @spec get_open_ai_auto_translation_enabled(map()) :: boolean
  def get_open_ai_auto_translation_enabled(organization) do
    FunWithFlags.enabled?(:is_open_ai_auto_translation_enabled,
      for: %{organization_id: organization.id}
    )
  end

  @doc """
  Get Google auto translation value for organization flag
  """
  @spec get_google_auto_translation_enabled(map()) :: boolean
  def get_google_auto_translation_enabled(organization) do
    FunWithFlags.enabled?(:is_google_auto_translation_enabled,
      for: %{organization_id: organization.id}
    )
  end

  @doc """
  Get contact profile value for organization flag
  """
  @spec get_contact_profile_enabled(map()) :: boolean
  def get_contact_profile_enabled(organization),
    do:
      FunWithFlags.enabled?(:is_contact_profile_enabled, for: %{organization_id: organization.id})

  @doc """
  Get ask_me bot value for organization flag
  """
  @spec get_ask_me_bot_enabled(map()) :: boolean
  def get_ask_me_bot_enabled(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_ask_me_bot_enabled, for: %{organization_id: organization.id}) ->
        true

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

  @doc """
  Get the status of given flag for the organization
  """
  @spec get_flag_enabled(atom(), map()) :: boolean
  def get_flag_enabled(flag, organization) do
    FunWithFlags.enabled?(flag, for: %{organization_id: organization.id})
  end

  @doc """
  Adds given flag to the organization map
  """
  @spec set_flag_enabled(map(), atom()) :: map()
  def set_flag_enabled(organization, flag) do
    Map.put(organization, flag, get_flag_enabled(flag, organization))
  end

  @doc """
  Get whatsapp form value for organization flag
  """
  @spec get_whatsapp_forms_enabled?(map()) :: boolean
  def get_whatsapp_forms_enabled?(organization) do
    app_env = Application.get_env(:glific, :environment)

    cond do
      FunWithFlags.enabled?(:is_whatsapp_forms_enabled, for: %{organization_id: organization.id}) ->
        true

      Glific.trusted_env?(app_env, organization.id) ->
        true

      true ->
        false
    end
  end

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
  Set fun_with_flag toggle for whatsapp group for an organization
  """
  @spec set_whatsapp_group_enabled(map()) :: map()
  def set_whatsapp_group_enabled(organization) do
    Map.put(
      organization,
      :is_whatsapp_group_enabled,
      get_whatsapp_group_enabled(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for custom certificate for an organization
  """
  @spec set_certificate_enabled(map()) :: map()
  def set_certificate_enabled(organization) do
    Map.put(
      organization,
      :is_certificate_enabled,
      get_certificate_enabled(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for ai-platform for an organization
  """
  @spec set_is_kaapi_enabled(map()) :: map()
  def set_is_kaapi_enabled(organization) do
    Map.put(
      organization,
      :is_kaapi_enabled,
      get_is_kaapi_enabled(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for Interactive Message re-response for an organization
  """
  @spec set_interactive_re_response_enabled(map()) :: map()
  def set_interactive_re_response_enabled(organization) do
    Map.put(
      organization,
      :is_interactive_re_response_enabled,
      get_interactive_re_response_enabled(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for OpenAI auto translation for an organization
  """
  @spec set_open_ai_auto_translation_enabled(map()) :: map()
  def set_open_ai_auto_translation_enabled(organization) do
    Map.put(
      organization,
      :is_open_ai_auto_translation_enabled,
      get_open_ai_auto_translation_enabled(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for Google auto translation for an organization
  """
  @spec set_auto_translation_enabled_for_google_trans(map()) :: map()
  def set_auto_translation_enabled_for_google_trans(organization) do
    Map.put(
      organization,
      :is_google_auto_translation_enabled,
      get_google_auto_translation_enabled(organization)
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

  @doc """
  Set fun_with_flag toggle for ask_me bot enabled for an organization
  """
  @spec set_is_ask_me_bot_enabled(map()) :: map()
  def set_is_ask_me_bot_enabled(organization) do
    Map.put(
      organization,
      :is_ask_me_bot_enabled,
      get_ask_me_bot_enabled(organization)
    )
  end

  @doc """
  Set fun_with_flag toggle for whatsapp forms enabled for an organization
  """
  @spec set_is_whatsapp_forms_enabled(map()) :: map()
  def set_is_whatsapp_forms_enabled(organization) do
    Map.put(
      organization,
      :is_whatsapp_forms_enabled,
      get_whatsapp_forms_enabled?(organization)
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
      :is_open_ai_auto_translation_enabled,
      :is_google_auto_translation_enabled,
      :is_whatsapp_group_enabled,
      :is_certificate_enabled,
      :is_kaapi_enabled,
      :is_interactive_re_response_enabled,
      :is_ask_me_bot_enabled,
      :is_whatsapp_forms_enabled,
      :high_trigger_tps_enabled,
      :unified_api_enabled
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
