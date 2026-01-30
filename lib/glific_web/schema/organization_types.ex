defmodule GlificWeb.Schema.OrganizationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Organization DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]
  import Ecto.Query, warn: false

  alias Glific.{Enums.OrganizationStatus, Partners, Repo, Settings.Language}
  alias GlificWeb.{Resolvers, Schema, Schema.Middleware.Authorize}

  object :organization_result do
    field(:organization, :organization)
    field(:errors, list_of(:input_error))
  end

  object :organization_services_result do
    field(:bigquery, :boolean)
    field(:google_cloud_storage, :boolean)
    field(:dialogflow, :boolean)
    field(:fun_with_flags, :boolean)
    field(:flow_uuid_display, :boolean)
    field(:roles_and_permission, :boolean)
    field(:contact_profile_enabled, :boolean)
    field(:ticketing_enabled, :boolean)
    field(:auto_translation_enabled, :boolean)
    field(:whatsapp_group_enabled, :boolean)
    field(:certificate_enabled, :boolean)
    field(:kaapi_enabled, :boolean)
    field(:ask_me_bot_enabled, :boolean)
    field(:errors, list_of(:input_error))
    field(:whatsapp_forms_enabled, :boolean)
    field(:unified_api_enabled, :boolean)
  end

  object :organization_export_result do
    field(:data, :json)
    field(:errors, list_of(:input_error))
  end

  object :enabled_day do
    field(:id, :integer)
    field(:enabled, :boolean)
  end

  object :out_of_office do
    field(:enabled, :boolean)
    field(:start_time, :time)
    field(:end_time, :time)
    field(:enabled_days, list_of(:enabled_day))
    field(:flow_id, :id)
    field(:default_flow_id, :id)
  end

  object :setting do
    field(:report_frequency, :string)
    field(:run_flow_each_time, :boolean)
    field(:low_balance_threshold, :string)
    field(:critical_balance_threshold, :string)
    field(:send_warning_mail, :boolean)
    field(:allow_bot_number_update, :boolean)
  end

  object :regx_flow do
    field(:flow_id, :id)
    field(:regx, :string)
    field(:regx_opt, :string)
  end

  object :organization do
    field(:id, :id)
    field(:name, :string)
    field(:shortcode, :string)
    field(:email, :string)
    field(:fields, :json)

    field :bsp, :provider do
      resolve(dataloader(Repo))
    end

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :default_language, :language do
      resolve(dataloader(Repo))
    end

    field(:out_of_office, :out_of_office)

    field(:setting, :setting)

    field(:regx_flow, :regx_flow)

    field(:newcontact_flow_id, :id)

    field(:optin_flow_id, :id)

    field(:is_active, :boolean)

    field(:is_approved, :boolean)

    field(:status, :organization_status_enum)

    field(:timezone, :string)

    field(:session_limit, :integer)

    field(:last_communication_at, :datetime)

    field :active_languages, list_of(:language) do
      resolve(fn organization, _, _ ->
        languages =
          Language
          |> where([l], l.id in ^organization.active_language_ids)
          |> order_by([l], l.label)
          |> Repo.all()

        {:ok, languages}
      end)
    end

    field :signature_phrase, :string do
      resolve(fn organization, _, %{context: %{current_user: current_user}} ->
        if Enum.member?(current_user.roles, :staff),
          do: {:ok, ""},
          else: {:ok, organization.signature_phrase}
      end)
    end

    field(:is_suspended, :boolean)
    field(:suspended_until, :datetime)

    field(:is_flow_uuid_display, :boolean)
    field(:is_roles_and_permission, :boolean)
    field(:is_contact_profile_enabled, :boolean)
    field(:is_ticketing_enabled, :boolean)
    field(:is_auto_translation_enabled, :boolean)
    field(:is_whatsapp_group_enabled, :boolean)
    field(:is_certificate_enabled, :boolean)
    field(:is_kaapi_enabled, :boolean)
    field(:is_whatsapp_forms_enabled, :boolean)
    field(:is_trial_org, :boolean)
    field(:trial_expiration_date, :datetime)
    field(:unified_api_enabled, :boolean)

    field(:inserted_at, :datetime)

    field(:updated_at, :datetime)
  end

  object :daily_usage do
    field(:date, :string)
    field(:cumulative_bill, :float)
    field(:discount, :float)
    field(:fep, :integer)
    field(:ftc, :integer)
    field(:gupshup_cap, :float)
    field(:gupshup_fees, :float)
    field(:incoming_msg, :integer)
    field(:outgoing_msg, :integer)
    field(:outgoing_media_msg, :integer)
    field(:marketing, :integer)
    field(:service, :integer)
    field(:utility, :integer)
    field(:template_msg, :integer)
    field(:template_media_msg, :integer)
    field(:total_fees, :float)
    field(:whatsapp_fees, :float)
    field(:total_msg, :integer)
  end

  @desc "Filtering options for organizations"
  input_object :organization_filter do
    @desc "Match the shortcode"
    field(:shortcode, :string)

    @desc "Match the display name"
    field(:name, :string)

    @desc "Match the email"
    field(:email, :string)

    @desc "Match the provider"
    field(:provider, :string)

    @desc "Match the default language"
    field(:default_language, :string)
  end

  input_object :enabled_day_input do
    field(:id, non_null(:integer))
    field(:enabled, non_null(:boolean))
  end

  input_object :out_of_office_input do
    field(:enabled, :boolean)
    field(:start_time, :time)
    field(:end_time, :time)
    field(:enabled_days, list_of(:enabled_day_input))
    field(:flow_id, :id)
    field(:default_flow_id, :id)
  end

  input_object :setting_input do
    field(:report_frequency, :string)
    field(:run_flow_each_time, :boolean)
    field(:low_balance_threshold, :string)
    field(:critical_balance_threshold, :string)
    field(:send_warning_mail, :boolean)
  end

  input_object :regx_flow_input do
    field(:flow_id, :id)
    field(:regx, :string)
    field(:regx_opt, :string)
  end

  input_object :delete_organization_input do
    field(:delete_organization_id, :id)
    field(:is_confirmed, :boolean)
  end

  input_object :organization_input do
    field(:name, :string)
    field(:shortcode, :string)
    field(:email, :string)
    field(:phone, :string)

    field(:bsp_id, :id)
    field(:contact_id, :id)
    field(:default_language_id, :id)

    field(:out_of_office, :out_of_office_input)
    field(:setting, :setting_input)
    field(:regx_flow, :regx_flow_input)

    field(:newcontact_flow_id, :id)
    field(:optin_flow_id, :id)

    field(:is_active, :boolean)

    field(:status, :organization_status_enum)

    field(:timezone, :string)

    field(:session_limit, :integer)

    field(:active_language_ids, list_of(:id))

    field(:signature_phrase, :string)

    field(:last_communication_at, :datetime)

    field(:fields, :json)
  end

  input_object :export_filter do
    field(:start_time, :datetime)
    field(:end_time, :datetime)
    field(:limit, :integer)
    field(:offset, :integer)
    field(:tables, list_of(:string))
  end

  object :organization_queries do
    @desc "get the details of one organization"
    field :organization, :organization_result do
      arg(:id, :id)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Partners.organization/3)
    end

    @desc "Get a list of all organizations filtered by various criteria"
    field :organizations, list_of(:organization) do
      arg(:filter, :organization_filter)
      arg(:opts, :opts)
      middleware(Authorize, :glific_admin)
      resolve(&Resolvers.Partners.organizations/3)
    end

    @desc "Get a count of all organizations filtered by various criteria"
    field :count_organizations, :integer do
      arg(:filter, :organization_filter)
      middleware(Authorize, :glific_admin)
      resolve(&Resolvers.Partners.count_organizations/3)
    end

    @desc "Checks if organization has an active cloud storage setup"
    field :attachments_enabled, :boolean do
      middleware(Authorize, :staff)

      resolve(fn _, _, %{context: %{current_user: user}} ->
        {:ok, Partners.attachments_enabled?(user.organization_id)}
      end)
    end

    @desc "Tracks action (various high level clicks) done by org users"
    field :tracker, :boolean do
      arg(:event, non_null(:string))
      middleware(Authorize, :staff)

      resolve(fn _, %{event: event}, %{context: %{current_user: user}} ->
        Glific.Metrics.increment(event, user.organization_id)
        {:ok, true}
      end)
    end

    @desc "Get a list of all organizations services"
    field :organization_services, :organization_services_result do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Partners.organization_services/3)
    end

    @desc "Export organization dynamic data"
    field :organization_export_data, :organization_export_result do
      arg(:filter, :export_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Partners.organization_export_data/3)
    end

    @desc "Export organization config data"
    field :organization_export_config, :organization_export_result do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Partners.organization_export_config/3)
    end

    @desc "Export organization stats data"
    field :organization_export_stats, :organization_export_result do
      arg(:filter, :export_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Partners.organization_export_stats/3)
    end

    field :timezones, list_of(:string) do
      middleware(Authorize, :admin)

      resolve(fn _, _, _ ->
        {:ok, Tzdata.zone_list()}
      end)
    end

    @desc "Get a list of all organizations status"
    field :organization_status, list_of(:organization_status_enum) do
      middleware(Authorize, :admin)

      resolve(fn _, _, _ ->
        {:ok, OrganizationStatus.__enum_map__()}
      end)
    end

    @desc "Get daily app usage"
    field :daily_app_usage, list_of(:daily_usage) do
      arg(:from_date, non_null(:date))
      arg(:to_date, non_null(:date))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.get_app_usage/3)
    end
  end

  object :organization_mutations do
    field :create_organization, :organization_result do
      arg(:input, non_null(:organization_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.create_organization/3)
    end

    field :update_organization, :organization_result do
      arg(:id, non_null(:id))
      arg(:input, :organization_input)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.update_organization/3)
    end

    field :delete_organization_test_data, :organization_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.delete_organization_test_data/3)
    end

    field :delete_organization, :organization_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.delete_organization/3)
    end

    field :update_organization_status, :organization_result do
      arg(:update_organization_id, non_null(:id))
      arg(:status, :organization_status_enum)
      middleware(Authorize, :glific_admin)
      resolve(&Resolvers.Partners.update_organization_status/3)
    end

    field :delete_inactive_organization, :organization_result do
      arg(:delete_organization_id, non_null(:id))
      arg(:is_confirmed, non_null(:boolean))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.delete_inactive_organization/3)
    end

    field :reset_organization, :string do
      arg(:reset_organization_id, non_null(:id))
      arg(:is_confirmed, non_null(:boolean))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.reset_organization/3)
    end
  end

  object :organization_subscriptions do
    field :simulator_release, :json do
      arg(:organization_id, non_null(:id))
      config(&Schema.config_fun/2)

      resolve(fn data, _, _ ->
        {:ok, data}
      end)
    end

    field :bsp_balance, :json do
      arg(:organization_id, non_null(:id))
      config(&Schema.config_fun/2)

      resolve(fn data, _, _ ->
        {:ok, data}
      end)
    end

    field :collection_count, :json do
      arg(:organization_id, non_null(:id))
      config(&Schema.config_fun/2)

      resolve(fn data, _, _ ->
        {:ok, data}
      end)
    end
  end
end
