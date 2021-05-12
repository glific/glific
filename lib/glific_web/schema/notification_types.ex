defmodule GlificWeb.Schema.NotificationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Notification DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :notification_result do
    field :notification, :notification
    field :errors, list_of(:input_error)
  end

  object :notification do
    field :id, :id
    field :category, :string
    field :entity, :json
    field :message, :string
    field :severity, :json
    field :is_read, :boolean
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :organization, :organization do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for notifications"
  input_object :notification_filter do
    @desc "Match the message"
    field :message, :string

    @desc "Match the category"
    field :category, :string

    @desc "Match is read status"
    field :is_read, :boolean

  end

  object :notification_queries do
    @desc "Get a list of all notifications filtered by various criteria"
    field :notifications, list_of(:notification) do
      arg(:filter, :notification_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Notifications.notifications/3)
    end

    @desc "Get a count of all notifications filtered by various criteria"
    field :count_notifications, :integer do
      arg(:filter, :notification_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Notifications.count_notifications/3)
    end
  end

  object :notification_mutations do
    field :mark_notification_as_read, :boolean do
      middleware(Authorize, :staff)
      resolve(&Resolvers.Notifications.mark_notification_as_read/3)
    end
  end
end
