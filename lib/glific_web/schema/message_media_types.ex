defmodule GlificWeb.Schema.MessageMediaTypes do
  @moduledoc """
  GraphQL Representation of Glific's MessageMedia DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :message_media_result do
    field :message_media, :message_media
    field :errors, list_of(:input_error)
  end

  object :message_media do
    field :id, :id
    field :url, :string
    field :source_url, :string
    field :thumbnail, :string
    field :caption, :string
    field :provider_media_id, :string
  end

  input_object :message_media_input do
    field :url, :string
    field :source_url, :string
    field :thumbnail, :string
    field :caption, :string
    field :provider_media_id, :string
  end

  object :message_media_queries do
    @desc "get the details of one message media"
    field :message_media, :message_media_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.message_media/3)
    end

    @desc "Get a list of all message_media"
    field :messages_media, list_of(:message_media) do
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.messages_media/3)
    end

    @desc "Get a count of all message media"
    field :count_messages_media, :integer do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.count_messages_media/3)
    end
  end

  object :message_media_mutations do
    field :create_message_media, :message_media_result do
      arg(:input, non_null(:message_media_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.create_message_media/3)
    end

    field :update_message_media, :message_media_result do
      arg(:id, non_null(:id))
      arg(:input, :message_media_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.update_message_media/3)
    end

    field :delete_message_media, :message_media_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.delete_message_media/3)
    end
  end
end
