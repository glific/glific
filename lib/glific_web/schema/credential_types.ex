defmodule GlificWeb.Schema.CredentialTypes do
  @moduledoc """
  GraphQL Representation of Glific's Organization Credential DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :credential_result do
    field :credential, :credential
    field :errors, list_of(:input_error)
  end

  object :credential do
    field :id, :id
    field :keys, :json
    field :secrets, :json
    field :is_active, :boolean

    field :provider, :provider do
      resolve(dataloader(Repo))
    end
  end

  input_object :credential_input do
    field :shortcode, :string
    field :keys, :json
    field :secrets, :json
    field :is_active, :boolean
  end

  object :credential_queries do
    @desc "get the details of organization's one credential by shortcode"
    field :credential, :credential_result do
      arg(:shortcode, non_null(:string))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.credential/3)
    end
  end

  object :credential_mutations do
    field :create_credential, :credential_result do
      arg(:input, non_null(:credential_input))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.create_credential/3)
    end

    field :update_credential, :credential_result do
      arg(:id, non_null(:id))
      arg(:input, :credential_input)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Partners.update_credential/3)
    end
  end
end
