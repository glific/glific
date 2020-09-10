defmodule GlificWeb.Schema.LanguageTypes do
  @moduledoc """
  GraphQL Representation of Glific's Language DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :language do
    field :id, :id
    field :label, :string
    field :label_locale, :string
    field :locale, :string
    field :is_active, :boolean
  end

  @desc "Filtering options for languages"
  input_object :language_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the locale"
    field :locale, :string
  end

  input_object :language_input do
    field :label, non_null(:string)
    field :label_locale, non_null(:string)
    field :locale, non_null(:string)
    field :is_active, :boolean
    field :is_reserved, :boolean
  end

  object :language_result do
    field :language, :language
    field :errors, list_of(:input_error)
  end

  object :language_queries do
    @desc "get the details of one language"
    field :language, :language_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Settings.language/3)
    end

    @desc "Get a list of all languages filtered by various criteria"
    field :languages, list_of(:language) do
      arg(:opts, :opts)
      arg(:filter, :language_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Settings.languages/3)
    end

    @desc "Get a count of all languages"
    field :count_languages, :integer do
      arg(:filter, :language_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Settings.count_languages/3)
    end
  end

  object :language_mutations do
    field :create_language, :language_result do
      arg(:input, non_null(:language_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Settings.create_language/3)
    end

    field :update_language, :language_result do
      arg(:id, non_null(:id))
      arg(:input, :language_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Settings.update_language/3)
    end

    field :delete_language, :language_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Settings.delete_language/3)
    end
  end
end
