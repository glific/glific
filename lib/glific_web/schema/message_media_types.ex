defmodule GlificWeb.Schema.MessageMediaTypes do
  @moduledoc """
  GraphQL Representation of Glific's MessageMedia DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

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
    field :wa_media_id, :string
  end

  # @desc "Filtering options for message media"
  # input_object :message_media_filter do
  #   @desc "Match the url"
  #   field :url, :string

  #   @desc "Match the source url"
  #   field :source_url, :string

  #   @desc "Match the thumbnail"
  #   field :thumbnail, :string

  #   @desc "Match the caption"
  #   field :caption, :string
  # end

  input_object :message_media_input do
    field :url, :string
    field :source_url, :string
    field :thumbnail, :string
    field :caption, :string
    field :wa_media_id, :string
  end

  object :message_media_queries do
    @desc "get the details of one message_media"
    field :message_media, :message_media_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Messages.message_media/3)
    end

    # @desc "Get a list of all message_media filtered by various criteria"
    # field :message_medias, list_of(:message_media) do
    #   arg(:filter, :message_media_filter)
    #   arg(:order, type: :sort_order, default_value: :asc)
    #   resolve(&Resolvers.MessageMedia.message_medias/3)
    # end
  end

  object :message_media_mutations do
    field :create_message_media, :message_media_result do
      arg(:input, non_null(:message_media_input))
      resolve(&Resolvers.Messages.create_message_media/3)
    end

    field :update_message_media, :message_media_result do
      arg(:id, non_null(:id))
      arg(:input, :message_media_input)
      resolve(&Resolvers.Messages.update_message_media/3)
    end

    field :delete_message_media, :message_media_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Messages.delete_message_media/3)
    end
  end
end
