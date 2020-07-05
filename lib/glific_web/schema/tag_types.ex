defmodule GlificWeb.Schema.TagTypes do
  @moduledoc """
  GraphQL Representation of Glific's Tag DataType
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :tag_result do
    field :tag, :tag
    field :errors, list_of(:input_error)
  end

  object :tag do
    field :id, :id
    field :label, :string
    field :description, :string
    field :is_active, :boolean
    field :is_reserved, :boolean
    field :keywords, list_of(:string)

    field :parent, :tag do
      resolve(dataloader(Repo))
    end

    field :language, :language do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for tags"
  input_object :tag_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the description"
    field :description, :string

    @desc "Match the parent"
    field :parent, :string

    @desc "Match the parent"
    field :parent_id, :integer

    @desc "Match a language"
    field :language, :string

    @desc "Match a language id"
    field :language_id, :integer

    @desc "Match the active flag"
    field :is_active, :boolean

    @desc "Match the reserved flag"
    field :is_reserved, :boolean
  end

  input_object :tag_input do
    field :label, :string
    field :description, :string
    field :is_active, :boolean
    field :is_reserved, :boolean
    field :language_id, :id
    field :keywords, list_of(:string)
  end

  object :tag_queries do
    @desc "get the details of one tag"
    field :tag, :tag_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Tags.tag/3)
    end

    @desc "Get a list of all tags filtered by various criteria"
    field :tags, list_of(:tag) do
      arg(:filter, :tag_filter)
      arg(:opts, :opts)
      resolve(&Resolvers.Tags.tags/3)
    end

    @desc "Get a count of all tags filtered by various criteria"
    field :count_tags, :integer do
      arg(:filter, :tag_filter)
      resolve(&Resolvers.Tags.count_tags/3)
    end
  end

  object :tag_mutations do
    field :create_tag, :tag_result do
      arg(:input, non_null(:tag_input))
      resolve(&Resolvers.Tags.create_tag/3)
    end

    field :update_tag, :tag_result do
      arg(:id, non_null(:id))
      arg(:input, :tag_input)
      resolve(&Resolvers.Tags.update_tag/3)
    end

    field :delete_tag, :tag_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Tags.delete_tag/3)
    end

    @desc "Remove unread tag from messages and returns a list of message ids"
    field :mark_all_message_as_read, list_of(:id) do
      arg(:contact_id, non_null(:gid))
      resolve(&Resolvers.Tags.mark_all_message_as_read/3)
    end
  end
end
