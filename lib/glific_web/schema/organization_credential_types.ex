defmodule GlificWeb.Schema.OrganizationCredentialTypes do
  @moduledoc """
  GraphQL Representation of Glific's Organization Credential DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :organization_credential_result do
    field :organization_credential, :organization_credential
    field :errors, list_of(:input_error)
  end

  object :organization_credential do
    field :id, :id
    field :shortcode, :string
    field :keys, :json
    field :secrets, :json
  end

  input_object :organization_credential_input do
    field :shortcode, :string
    field :keys, :json
    field :secrets, :json
  end

  object :organization_credential_queries do
    @desc "get the details of organization's one credential by shortcode"
    field :organization_credential, :organization_credential_result do
      arg(:shortcode, non_null(:string))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.organization_credential/3)
    end
  end

  object :organization_credential_mutations do
    field :create_organization_credential, :organization_credential_result do
      arg(:input, non_null(:organization_credential_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.create_organization_credential/3)
    end

    field :update_organization_credential, :organization_credential_result do
      arg(:id, non_null(:id))
      arg(:input, :organization_credential_input)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.update_organization_credential/3)
    end
  end
end
