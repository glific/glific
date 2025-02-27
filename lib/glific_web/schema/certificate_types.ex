defmodule GlificWeb.Schema.CertificateTypes do
  @moduledoc """
   GraphQL Representation of Glific's Certificates
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers

  alias Glific.Repo
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
  end

  object :certificate_mutations do
    @desc "Create certificate template"
    field :create_certificate_template, :certificate_template_result do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Filesearch.create_assistant/3)
    end
  end
end
