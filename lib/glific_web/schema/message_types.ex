defmodule GlificWeb.Schema.MessageTypes do
  @moduledoc """
  GraphQL Representation of Glific's Message DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 2]

  alias Glific.Repo

  alias GlificWeb.{
    Resolvers,
    Schema,
    Schema.Middleware.Authorize
  }

  object :message_result do
    field :message, :message
    field :errors, list_of(:input_error)
  end

  object :group_message_result do
    field :success, :boolean
    field :contact_ids, list_of(:id)
    field :errors, list_of(:input_error)
  end

  object :clear_messages_result do
    field :success, :boolean
    field :errors, list_of(:input_error)
  end

  object :message do
    field :id, :id
    field :body, :string
    field :type, :message_type_enum
    field :flow, :message_flow_enum
    field :bsp_message_id, :string
    field :status, :string
    field :errors, :json
    field :message_number, :integer

    field :is_hsm, :boolean

    field :template_id, :integer
    field :group_id, :integer
    field :params, list_of(:string)

    field :bsp_status, :message_status_enum

    # expose the date we processed this message since external clients need it
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :send_at, :datetime

    field :sender, :contact do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :receiver, :contact do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :contact, :contact do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :user, :user do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :media, :message_media do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :location, :locations do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :tags, list_of(:tag) do
      resolve(dataloader(Repo, use_parent: true))
    end
  end

  @desc "Filtering options for messages"
  input_object :message_filter do
    @desc "Match the namebody"
    field :body, :string

    @desc "Match the sender"
    field :sender, :string

    @desc "Match the receiver"
    field :receiver, :string

    @desc "Match the phone with either the sender or receiver"
    field :either, :string

    @desc "Match the user"
    field :user, :string

    @desc "Match the status"
    field :bsp_status, :message_status_enum

    @desc "Match the tags included"
    field :tags_included, list_of(:id)

    @desc "Match the tags excluded"
    field :tags_excluded, list_of(:id)
  end

  input_object :message_input do
    field :body, :string
    field :type, :message_type_enum
    field :flow, :message_flow_enum

    field :sender_id, :id
    field :receiver_id, :id
    field :media_id, :id

    field :send_at, :datetime
    field :is_hsm, :boolean
    field :template_id, :integer
    field :params, list_of(:string)
  end

  object :message_queries do
    @desc "get the details of one message"
    field :message, :message_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.message/3)
    end

    @desc "Get a list of all messages filtered by various criteria"
    field :messages, list_of(:message) do
      arg(:filter, :message_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.messages/3)
    end

    @desc "Get a count of all messages filtered by various criteria"
    field :count_messages, :integer do
      arg(:filter, :message_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.count_messages/3)
    end
  end

  object :message_mutations do
    field :create_message, :message_result do
      arg(:input, non_null(:message_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.create_message/3)
    end

    field :create_and_send_message, :message_result do
      arg(:input, non_null(:message_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.create_and_send_message/3)
    end

    field :create_and_send_message_to_group, :group_message_result do
      arg(:input, non_null(:message_input))
      arg(:group_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.create_and_send_message_to_group/3)
    end

    field :send_hsm_message, :message_result do
      arg(:template_id, non_null(:id))
      arg(:receiver_id, non_null(:id))
      arg(:parameters, list_of(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.send_hsm_message/3)
    end

    field :send_session_message, :message_result do
      arg(:id, non_null(:id))
      arg(:receiver_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.send_session_message/3)
    end

    field :update_message, :message_result do
      arg(:id, non_null(:id))
      arg(:input, :message_input)
      middleware(Authorize, :admin)
      resolve(&Resolvers.Messages.update_message/3)
    end

    field :delete_message, :message_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :admin)
      resolve(&Resolvers.Messages.delete_message/3)
    end

    field :clear_messages, :clear_messages_result do
      arg(:contact_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.clear_messages/3)
    end
  end

  object :message_subscriptions do
    field :received_message, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Resolvers.Messages.publish_message/3)
    end

    field :sent_message, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Resolvers.Messages.publish_message/3)
    end

    field :cleared_messages, :contact do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn contact, _, _ -> {:ok, contact} end)
    end

    field :update_message_status, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn message, _, _ -> {:ok, message} end)
    end

    field :sent_group_message, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn message, _, _ -> {:ok, message} end)
    end
  end
end
