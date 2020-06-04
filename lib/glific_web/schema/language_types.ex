defmodule GlificWeb.Schema.LanguageTypes do
  @moduledoc """
  GraphQL Representation of Glific's Language DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :language do
    interfaces([:search_result])
    field :id, :id
    field :label, :string
    field :locale, :string
    field :is_active, :boolean

    field :tags, list_of(:tag) do
      resolve(&Resolvers.Tags.tags_for_language/3)
    end
  end

  input_object :language_input do
    field :label, non_null(:string)
    field :locale, non_null(:string)
    field :is_active, :boolean
    field :is_reserved, :boolean
  end

  object :language_result do
    field :language, :language
    field :errors, list_of(:input_error)
  end

  object :language_queries do
    field :languages, list_of(:language) do
      resolve(&Resolvers.Settings.languages/3)
    end
  end

  object :language_mutations do
    field :create_language, :language_result do
      arg(:input, non_null(:language_input))
      resolve(&Resolvers.Settings.create_language/3)
    end
  end
end
