defmodule GlificWeb.Resolvers.Notifications do
  @moduledoc """
  Notification Resolver which sits between the GraphQL schema and Glific Notification Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Notifications,
    Notifications.Notification
  }

  @doc """
  Get the list of notifications filtered by args
  """
  @spec notifications(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Notification]}
  def notifications(_, args, _) do
    {:ok, Notifications.list_notifications(args)}
  end

  @doc """
  Get the count of notifications filtered by args
  """
  @spec count_notifications(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_notifications(_, args, _) do
    {:ok, Notifications.count_notifications(args)}
  end

  @doc """
  Mark all the unread messages as read
  """
  @spec mark_notification_as_read(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, boolean()}
  def mark_notification_as_read(_, _args, _) do
    {:ok, Notifications.mark_notification_as_read()}
  end
end
