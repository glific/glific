defmodule GlificWeb.Schema.MessageTagTypes do
  @moduledoc """
  GraphQL Representation of Glific's Message Tag DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo

  alias GlificWeb.{
    Resolvers,
    Schema,
    Schema.Middleware.Authorize
  }

  object :message_tag_result do
    field :message_tag, :message_tag
    field :errors, list_of(:input_error)
  end

  object :message_tag do
    field :id, :id

    field :value, :string

    field :message, :message do
      resolve(dataloader(Repo))
    end

    field :tag, :tag do
      resolve(dataloader(Repo))
    end
  end

  object :message_tags do
    field :number_deleted, :integer
    field :message_tags, list_of(:message_tag)
  end

  input_object :message_tag_input do
    field :message_id, :id
    field :tag_id, :id
  end

  input_object :message_tags_input do
    field :message_id, non_null(:id)
    field :add_tag_ids, non_null(list_of(:id))
    field :delete_tag_ids, non_null(list_of(:id))
  end

  object :message_tag_mutations do
    field :create_message_tag, :message_tag_result do
      arg(:input, non_null(:message_tag_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Tags.create_message_tag/3)
    end

    field :update_message_tags, :message_tags do
      arg(:input, non_null(:message_tags_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Tags.update_message_tags/3)
    end
  end

  object :message_tag_subscriptions do
    field :created_message_tag, :message_tag do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn message_tag, _, _ -> {:ok, message_tag} end)
    end

    field :deleted_message_tag, :message_tag do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn message_tag, _, _ -> {:ok, message_tag} end)
    end
  end
end
