defmodule GlificWeb.Schema.CertificateTypes do
  @moduledoc """
   GraphQL Representation of Glific's Certificates
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :certificate_template_result do
    field :certificate_template, :certificate_template
    field :errors, list_of(:input_error)
  end

  object :certificate_template do
    field :id, :id
    field :label, :string
    field :url, :string
    field :description, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  input_object :certificate_template_input do
    field :label, :string
    field :url, :string
    field :description, :string
    field :type, :string
  end

  @desc "Filtering options for Certificate templates"
  input_object :certificate_template_filter do
    @desc "Match the label"
    field(:label, :string)
  end

  object :certificate_mutations do
    @desc "Create certificate template"
    field :create_certificate_template, :certificate_template_result do
      arg(:input, non_null(:certificate_template_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Certificate.create_certificate_template/3)
    end

    @desc "Update certificate template"
    field :update_certificate_template, :certificate_template_result do
      arg(:input, non_null(:certificate_template_input))
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Certificate.update_certificate_template/3)
    end

    @desc "Delete certificate template"
    field :delete_certificate_template, :certificate_template_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Certificate.delete_certificate_template/3)
    end
  end

  object :certificate_queries do
    @desc "Get Certificate template"
    field :certificate_template, :certificate_template_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Certificate.get_certificate_template/3)
    end

    @desc "Get a list of all certificate templates filtered by various criteria"
    field :certificate_templates, list_of(:certificate_template) do
      arg(:filter, :certificate_template_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Certificate.list_certificate_templates/3)
    end

    @desc "Get a count of all certificate templates filtered by various criteria"
    field :count_certificate_templates, :integer do
      arg(:filter, :certificate_template_filter)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Certificate.count_certificate_templates/3)
    end
  end
end
