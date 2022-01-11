defmodule Glific.Notifications do
  @moduledoc """
  The notifications manager and API to interface with the notification sub-system
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Communications.Mailer,
    Mails.CriticalNotificationMail,
    Notifications.Notification,
    Partners,
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
    |> case do
      {:ok, notification} ->
        if Glific.string_clean(attrs.severity) == "critical" do
          handle_critical_notification(notification)
        end

        {:ok, notification}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Update a Notification
  """
  @spec update_notification(Notification.t(), map()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def update_notification(notification, attrs) do
    notification
    |> Notification.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the list of notifications.
  Since this is very basic and only listing functionality we added the status filter like this.
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

      {:severity, severity}, query ->
        from q in query, where: ilike(q.severity, ^"%#{severity}%")

      {:is_read, is_read}, query ->
        from q in query, where: q.is_read == ^is_read

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

  @doc """
  Mark all the unread messages as read.
  """
  @spec mark_notification_as_read() :: boolean
  def mark_notification_as_read do
    Notification
    |> where([n], n.is_read == false)
    |> Repo.update_all(set: [is_read: true])

    true
  end

  defp handle_critical_notification(notification) do
    {:ok, _} =
      Partners.organization(notification.organization_id)
      |> CriticalNotificationMail.new_mail(notification.message)
      |> Mailer.send(%{
        category: "critical_notification",
        organization_id: notification.organization_id
      })
  end
end
