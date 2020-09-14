defmodule GlificWeb.Schema.OrganizationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Organization DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]
  import Ecto.Query, warn: false

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :organization_result do
    field :organization, :organization
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
  end

  object :organization do
    field :id, :id
    field :name, :string
    field :shortcode, :string
    field :provider_appname, :string
    field :email, :string
    field :provider_phone, :string

    field :provider, :provider do
      resolve(dataloader(Repo))
    end

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :default_language, :language do
      resolve(dataloader(Repo))
    end

    field :out_of_office, :out_of_office

    field :is_active, :boolean

    field :timezone, :string

    field :active_languages, list_of(:language) do
      resolve(fn organization, _, _ ->
        languages =
          Glific.Settings.Language
          |> Ecto.Query.where([l], l.id in ^organization.active_languages)
          |> Repo.all()

        {:ok, languages}
      end)
    end
  end

  @desc "Filtering options for organizations"
  input_object :organization_filter do
    @desc "Match the shortcode"
    field :shortcode, :string

    @desc "Match the display name"
    field :name, :string

    @desc "Match the email"
    field :email, :string

    @desc "Match the whatsapp number of organization"
    field :provider_phone, :string

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
  end

  input_object :organization_input do
    field :name, :string
    field :shortcode, :string
    field :email, :string
    field :provider_appname, :string
    field :provider_phone, :string

    field :provider_id, :id
    field :contact_id, :id
    field :default_language_id, :id

    field :out_of_office, :out_of_office_input

    field :is_active, :boolean

    field :timezone, :string

    field :active_languages, list_of(:id)
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

    field :timezones, list_of(:string) do
      middleware(Authorize, :admin)

      resolve(fn _, _, _ ->
        {:ok, Tzdata.zone_list()}
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
  end
end
