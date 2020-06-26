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

    field :value, :string

    field :message, :message do
      resolve(dataloader(Repo))
    end

    field :tag, :tag do
      resolve(dataloader(Repo))
    end
  end

  object :message_tags do
    field :message_tags, list_of(:message_tag)
  end

  input_object :message_tag_input do
    field :message_id, :id
    field :tag_id, :id
  end

  input_object :message_tags_input do
    field :message_id, :id
    field :tags_id, list_of(:id)
  end

  object :message_tag_mutations do
    field :create_message_tag, :message_tag_result do
      arg(:input, non_null(:message_tag_input))
      resolve(&Resolvers.Tags.create_message_tag/3)
    end

    field :create_message_tags, :message_tags do
      arg(:input, non_null(:message_tags_input))
      resolve(&Resolvers.Tags.create_message_tags/3)
    end

    field :delete_message_tag, :message_tag_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Tags.delete_message_tag/3)
    end
  end

  object :message_tag_subscriptions do
    field :created_message_tag, :message_tag do
      config(fn _args, _info ->
        {:ok, topic: :glific}
      end)

      trigger(
        [:create_message_tag],
        :glific
      )

      resolve(fn %{message_tag: message_tag}, _, _ ->
        {:ok, message_tag}
      end)
    end

    field :deleted_message_tag, :message_tag do
      config(fn _args, _info ->
        {:ok, topic: :glific}
      end)

      trigger(
        [:delete_message_tag],
        :glific
      )

      resolve(fn %{message_tag: message_tag}, _, _ ->
        {:ok, message_tag}
      end)
    end
  end
end
