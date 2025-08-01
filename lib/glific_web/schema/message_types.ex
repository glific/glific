defmodule GlificWeb.Schema.MessageTypes do
  @moduledoc """
  GraphQL Representation of Glific's Message DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 2]

  alias Glific.{
    Messages.Message,
    Repo
  }

  alias GlificWeb.{
    Resolvers,
    Schema,
    Schema.Middleware.Authorize
  }

  object :message_result do
    field :message, :message
    field :errors, list_of(:input_error)
  end

  object :wa_message_result do
    field :errors, list_of(:input_error)
  end

  object :collection_wa_message_result do
    field :success, :boolean
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
    field :uuid, :string
    field :type, :message_type_enum
    field :flow, :message_flow_enum
    field :flow_label, :string
    field :bsp_message_id, :string
    field :status, :string
    field :errors, :json
    field :message_number, :integer

    field :send_by, :string do
      resolve(fn message, _, _ ->
        updated_message =
          message
          |> Repo.preload([:flow_object, :user])
          |> Message.append_send_by()

        {:ok, updated_message.send_by}
      end)
    end

    field :is_hsm, :boolean

    field :template_id, :integer
    field :group_id, :integer
    field :params, list_of(:string)

    field :bsp_status, :message_status_enum

    # expose the date we processed this message since external clients need it
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :send_at, :datetime

    field :interactive_content, :json

    # the context of this message if applicable
    # basically links to the message which the user
    # replied to
    field :context_id, :string
    field :message_broadcast_id, :string

    field :context_message, :message do
      resolve(dataloader(Repo, use_parent: true))
    end

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

  object :wa_message do
    field :id, :id
    field :body, :string
    field :type, :message_type_enum
    field :flow, :message_flow_enum
    field :message_number, :integer
    field :bsp_id, :string
    field :bsp_status, :message_status_enum
    field :send_at, :datetime
    field :status, :string
    field :errors, :json
    field :is_dm, :boolean

    # expose the date we processed this message since external clients need it
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :group_id, :integer
    field :context_id, :string
    field :poll_content, :json

    field :context_message, :wa_message do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :contact, :contact do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :wa_managed_phone, :wa_managed_phone do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :media, :message_media do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :wa_group, :wa_group do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :location, :locations do
      resolve(dataloader(Repo, use_parent: true))
    end

    field :poll, :wa_poll do
      resolve(dataloader(Repo, use_parent: true))
    end
  end

  @desc "Filtering options for messages"
  input_object :message_filter do
    @desc "Match the name body"
    field :body, :string

    @desc "Match the sender"
    field :sender, :string

    @desc "Match the receiver"
    field :receiver, :string

    @desc "Match the message types"
    field :types, list_of(:message_type_enum)

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

    @desc "a static date range input field which will apply on updated at column."
    field :date_range, :date_range_input

    @desc "Match the flow id"
    field :flow_id, :id
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
    field :interactive_template_id, :integer
    field :params, list_of(:string)
  end

  input_object :wa_message_input do
    field :message, :string
    field :type, :message_type_enum

    field :media_id, :id
    field :wa_managed_phone_id, :id
    field :wa_group_id, :id
    field :poll_id, :integer
  end

  input_object :collection_wa_message_input do
    field :message, :string
    field :type, :message_type_enum

    field :media_id, :id
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
      arg(:parameters, list_of(:string))
      arg(:receiver_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.send_hsm_message/3)
    end

    field :send_hsm_message_to_group, :group_message_result do
      arg(:template_id, non_null(:id))
      arg(:parameters, list_of(:string))
      arg(:group_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.send_hsm_message_to_group/3)
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

    field :send_message_in_wa_group, :wa_message_result do
      arg(:input, non_null(:wa_message_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.send_message_in_wa_group/3)
    end

    field :send_message_to_wa_group_collection, :collection_wa_message_result do
      arg(:input, non_null(:collection_wa_message_input))
      arg(:group_id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Messages.send_message_to_wa_group_collection/3)
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

    field :received_wa_group_message, :wa_message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Resolvers.Messages.publish_message/3)
    end

    field :sent_wa_group_message, :wa_message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Resolvers.Messages.publish_message/3)
    end

    field :received_simulator_message, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Resolvers.Messages.publish_message/3)
    end

    field :sent_simulator_message, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(&Resolvers.Messages.publish_message/3)
    end

    # These are used to send the status such as error for
    # a particular message to the FE, so it can flag it (in error's case)
    field :update_message_status, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn message, _, _ -> {:ok, message} end)
    end

    field :update_wa_message_status, :wa_message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn wa_message, _, _ -> {:ok, wa_message} end)
    end

    field :sent_group_message, :message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn message, _, _ -> {:ok, message} end)
    end

    field :sent_wa_group_collection_message, :wa_message do
      arg(:organization_id, non_null(:id))

      config(&Schema.config_fun/2)

      resolve(fn wa_message, _, _ -> {:ok, wa_message} end)
    end
  end
end
