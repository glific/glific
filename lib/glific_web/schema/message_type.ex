defmodule GlificWeb.Schema.MessageTypes do
  @moduledoc """
  GraphQL Representation of Glific's Message DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :message_result do
    field :message, :message
    field :errors, list_of(:input_error)
  end

  object :message do
    field :id, :id
    field :body, :string
    field :type, :message_types_enum
    field :flow, :message_flow_enum
    field :wa_message_id, :string

    field :wa_status, :message_status_enum

    field :sender, :contact do
      resolve(dataloader(Repo))
    end

    field :recipient, :contact do
      resolve(dataloader(Repo))
    end

    # field :media, :message_media do
    #   resolve(dataloader(Message))
    # end

    field :tags, list_of(:tag) do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for messages"
  input_object :message_filter do
    @desc "Match the namebody"
    field :body, :string

    @desc "Match the sender"
    field :sender, :string

    @desc "Match the recipient"
    field :recipient, :string

    @desc "Match the phone with either the sender or receiver"
    field :either, :string

    @desc "Match the status"
    field :wa_status, :message_status_enum
  end

  input_object :message_input do
    field :body, :string
    field :type, :message_types_enum
    field :flow, :message_flow_enum
    field :wa_message_id, :string

    field :wa_status, :message_status_enum

    field :sender_id, :id
    field :recipient_id, :id
    field :media_id, :id
  end

  object :message_queries do
    @desc "get the details of one message"
    field :message, :message_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Messages.message/3)
    end

    @desc "Get a list of all messages filtered by various criteria"
    field :messages, list_of(:message) do
      arg(:filter, :message_filter)
      arg(:order, type: :sort_order, default_value: :asc)
      resolve(&Resolvers.Messages.messages/3)
    end
  end

  object :message_mutations do
    field :create_message, :message_result do
      arg(:input, non_null(:message_input))
      resolve(&Resolvers.Messages.create_message/3)
    end

    # field :send_message, :message_result do
    #   arg(:input, non_null(:message_input))
    #   resolve(&Resolvers.Messages.send_message/3)
    # end

    field :update_message, :message_result do
      arg(:id, non_null(:id))
      arg(:input, :message_input)
      resolve(&Resolvers.Messages.update_message/3)
    end

    field :delete_message, :message_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Messages.delete_message/3)
    end
  end

  object :message_subscriptions do
    field :received_message, :message do
      config(fn _args, _info ->
        {:ok, topic: "*"}
      end)
    end

    field :sent_message, :message do
      arg(:id, non_null(:id))

      config(fn args, _info ->
        {:ok, topic: args.id}
      end)

      trigger([:send_message],
        topic: fn
          %{message: message} -> message.id
          _ -> []
        end
      )

      resolve(fn %{message: message}, _, _ ->
        {:ok, message}
      end)
    end
  end
end
