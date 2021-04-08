defmodule Glific.Notifications do
  @moduledoc """
  The notifications manager and API to interface with the notification sub-system
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Notifications.Notification,
    Repo
  }

  @doc """
  Create a Notification
  """
  @spec create_notification(map()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a Notification
  """
  @spec update_notification(Notification.t(), map()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def update_notification(log, attrs) do
    log
    |> Notification.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the list of notifications.
  Since this is very basic and only listing funcatinality we added the status filter like this.
  In future we will put the status as virtual filed in the notifications itself.
  """
  @spec list_notifications(map()) :: list()
  def list_notifications(args),
    do: Repo.list_filter(args, Notification, &Repo.opts_with_inserted_at/2, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to notifications only.
    # We might want to move them in the repo in the future.

    Enum.reduce(filter, query, fn
      {:category, category}, query ->
        from q in query, where: q.category == ^category

      {:message, message}, query ->
        from q in query, where: ilike(q.message, ^"%#{message}%")

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of notifications, using the same filter as list_notifications
  """
  @spec count_notifications(map()) :: integer
  def count_notifications(args),
    do: Repo.count_filter(args, Notification, &filter_with/2)
end
