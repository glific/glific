defmodule GlificWeb.Schema.MessageTagTypes do
  @moduledoc """
  GraphQL Representation of Glific's Message Tag DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :message_tag_result do
    field :message_tag, :message_tag
    field :errors, list_of(:input_error)
  end

  object :message_tag do
    field :id, :id

    field :message, :message do
      resolve(dataloader(Repo))
    end

    field :tag, :tag do
      resolve(dataloader(Repo))
    end
  end

  input_object :message_tag_input do
    field :message_id, :id
    field :tag_id, :id
  end

  object :message_tag_queries do
    field :message_tag, :message_tag_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Tags.message_tag/3)
    end
  end

  object :message_tag_mutations do
    field :create_message_tag, :message_tag_result do
      arg(:input, non_null(:message_tag_input))
      resolve(&Resolvers.Tags.create_message_tag/3)
    end

    field :delete_message_tag, :message_tag_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Tags.delete_message_tag/3)
    end
  end
end
