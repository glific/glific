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
    field :organization, :organization
    field :errors, list_of(:input_error)
  end

  object :organization_services_result do
    field :bigquery, :boolean
    field :google_cloud_storage, :boolean
    field :dialogflow, :boolean
    field :fun_with_flags, :boolean
    field :errors, list_of(:input_error)
  end

  object :enabled_day do
    field :id, :integer
    field :enabled, :boolean
  end

  object :out_of_office do
    field :enabled, :boolean
    field :start_time, :time
    field :end_time, :time
    field :enabled_days, list_of(:enabled_day)
    field :flow_id, :id
    field :default_flow_id, :id
  end

  object :organization do
    field :id, :id
    field :name, :string
    field :shortcode, :string
    field :email, :string
    field :fields, :json

    field :bsp, :provider do
      resolve(dataloader(Repo))
    end

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :default_language, :language do
      resolve(dataloader(Repo))
    end

    field :out_of_office, :out_of_office

    field :newcontact_flow_id, :id

    field :is_active, :boolean

    field :is_approved, :boolean

    field :status, :organization_status_enum

    field :timezone, :string

    field :session_limit, :integer

    field :last_communication_at, :datetime

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

    field :inserted_at, :datetime

    field :updated_at, :datetime
  end

  @desc "Filtering options for organizations"
  input_object :organization_filter do
    @desc "Match the shortcode"
    field :shortcode, :string

    @desc "Match the display name"
    field :name, :string

    @desc "Match the email"
    field :email, :string

    @desc "Match the provider"
    field :provider, :string

    @desc "Match the default language"
    field :default_language, :string
  end

  input_object :enabled_day_input do
    field :id, non_null(:integer)
    field :enabled, non_null(:boolean)
  end

  input_object :out_of_office_input do
    field :enabled, :boolean
    field :start_time, :time
    field :end_time, :time
    field :enabled_days, list_of(:enabled_day_input)
    field :flow_id, :id
    field :default_flow_id, :id
  end

  input_object :delete_organization_input do
    field :delete_organization_id, :id
    field :is_confirmed, :boolean
  end

  input_object :organization_input do
    field :name, :string
    field :shortcode, :string
    field :email, :string

    field :bsp_id, :id
    field :contact_id, :id
    field :default_language_id, :id

    field :out_of_office, :out_of_office_input
    field :newcontact_flow_id, :id

    field :is_active, :boolean

    field :status, :organization_status_enum

    field :timezone, :string

    field :session_limit, :integer

    field :active_language_ids, list_of(:id)

    field :signature_phrase, :string

    field :last_communication_at, :datetime

    field :fields, :json
  end

  object :organization_queries do
    @desc "get the details of one organization"
    field :organization, :organization_result do
      arg(:id, :id)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.organization/3)
    end

    @desc "Get a list of all organizations filtered by various criteria"
    field :organizations, list_of(:organization) do
      arg(:filter, :organization_filter)
      arg(:opts, :opts)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.organizations/3)
    end

    @desc "Get a count of all organizations filtered by various criteria"
    field :count_organizations, :integer do
      arg(:filter, :organization_filter)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.count_organizations/3)
    end

    @desc "Checks if organization has an active cloud storage setup"
    field :attachments_enabled, :boolean do
      middleware(Authorize, :staff)

      resolve(fn _, _, %{context: %{current_user: user}} ->
        {:ok, Partners.attachments_enabled?(user.organization_id)}
      end)
    end

    @desc "Get a list of all organizations services"
    field :organization_services, :organization_services_result do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Partners.organization_services/3)
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

    field :delete_organization, :organization_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.delete_organization/3)
    end

    field :update_organization_status, :organization_result do
      arg(:update_organization_id, non_null(:id))
      arg(:status, :organization_status_enum)
      middleware(Authorize, :admin)
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
