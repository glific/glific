defmodule Glific.Tickets do
  @moduledoc """
  The Tickets context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.Action,
    Flows.FlowContext,
    Flows.MessageVarParser,
    Messages,
    Notifications,
    Repo,
    Tickets.Ticket,
    Users.User
  }

  @beginning_of_day ~T[00:00:00.000]
  @end_of_day ~T[23:59:59.000]

  @doc """
  Returns the list of tickets.

  ## Examples

      iex> list_tickets()
      [%Ticket{}, ...]

  """
  @spec list_tickets(map()) :: [Ticket.t()]
  def list_tickets(args),
    do: Repo.list_filter(args, Ticket, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of tickets, using the same filter as list_tickets
  """
  @spec count_tickets(map()) :: integer
  def count_tickets(args),
    do: Repo.count_filter(args, Ticket, &filter_with/2)

  @doc """
  Gets a single ticket.

  Raises `Ecto.NoResultsError` if the Ticket does not exist.

  ## Examples

      iex> get_ticket!(123)
      %Ticket{}

      iex> get_ticket!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_ticket!(non_neg_integer) :: Ticket.t()
  def get_ticket!(id), do: Repo.get!(Ticket, id)

  @doc """
  Creates a ticket.

  ## Examples

      iex> create_ticket(%{field: value})
      {:ok, %Ticket{}}

      iex> create_ticket(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_ticket(map()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def create_ticket(attrs \\ %{}) do
    ticket_params = Map.put_new(attrs, :status, "open")

    with {:ok, ticket} <- do_create_ticket(ticket_params),
         {:ok, _notification} <- create_ticket_notification(attrs) do
      {:ok, ticket}
    end
  end

  @spec do_create_ticket(map()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  defp do_create_ticket(params) do
    %Ticket{}
    |> Ticket.changeset(params)
    |> Repo.insert()
  end

  @spec create_ticket_notification(map()) :: map()
  defp create_ticket_notification(attrs) do
    %{
      category: "Ticket",
      message: "New Ticket created",
      severity: Notifications.types().info,
      organization_id: attrs.organization_id,
      entity: %{query: attrs.body}
    }
    |> Notifications.create_notification()
  end

  @doc """
  Updates a ticket.

  ## Examples

      iex> update_ticket(ticket, %{field: new_value})
      {:ok, %Ticket{}}

      iex> update_ticket(ticket, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_ticket(Ticket.t(), map()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def update_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a ticket.

  ## Examples

      iex> delete_ticket(ticket)
      {:ok, %Ticket{}}

      iex> delete_ticket(ticket)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_ticket(Ticket.t()) :: {:ok, Ticket.t()} | {:error, Ecto.Changeset.t()}
  def delete_ticket(%Ticket{} = ticket) do
    Repo.delete(ticket)
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        from(q in query, where: q.status == ^status)

      {:contact_id, contact_id}, query ->
        from(q in query, where: q.contact_id == ^contact_id)

      {:user_id, user_id}, query ->
        from(q in query, where: q.user_id == ^user_id)

      _, query ->
        query
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ticket changes.

  ## Examples

      iex> change_ticket(ticket)
      %Ecto.Changeset{data: %Ticket{}}

  """
  @spec change_ticket(Ticket.t(), map()) :: Ecto.Changeset.t()
  def change_ticket(%Ticket{} = ticket, attrs \\ %{}) do
    Ticket.changeset(ticket, attrs)
  end

  @doc """
  Execute a sheet action
  """
  @spec execute(Action.t() | any(), FlowContext.t()) :: {FlowContext.t(), Messages.Message.t()}
  def execute(action, context) do
    fields = FlowContext.get_vars_to_parse(context)

    ticket_body = MessageVarParser.parse(action.body, fields)

    ticket_params = %{
      body: ticket_body,
      topic: action.topic,
      user_id: action.assignee,
      contact_id: context.contact_id,
      organization_id: context.organization_id
    }

    case create_ticket(ticket_params) do
      {:ok, _response} ->
        {context, Messages.create_temp_message(context.organization_id, "Success")}

      {:error, _response} ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  @doc """
  Return the count of support ticket, using the same filter as list_supporting
  """
  @spec fetch_support_tickets(map()) :: String.t()
  def fetch_support_tickets(args) do
    start_time = DateTime.new!(args.filter.start_date, @beginning_of_day, "Etc/UTC")
    end_time = DateTime.new!(args.filter.end_date, @end_of_day, "Etc/UTC")
    org_id = args.organization_id

    Ticket
    |> join(:left, [t], c in Contact, as: :c, on: c.id == t.contact_id)
    |> join(:left, [t], u in User, as: :u, on: u.id == t.user_id)
    |> where([t], t.inserted_at >= ^start_time and t.inserted_at <= ^end_time)
    |> where([t], t.organization_id == ^org_id)
    |> select([t, c, u], %{
      body: t.body,
      status: t.status,
      topic: t.topic,
      inserted_at: t.inserted_at,
      opened_by: c.name,
      assigned_to: u.name
    })
    |> Repo.all()
    |> convert_to_csv_string()
  end

  @default_headers "body,status,topic,inserted_at,opened_by,assigned_to\n"

  @doc false
  @spec convert_to_csv_string([Ticket.t()]) :: String.t()
  def convert_to_csv_string(ticket) do
    ticket
    |> Enum.reduce(@default_headers, fn ticket, acc ->
      acc <> minimal_map(ticket) <> "\n"
    end)
  end

  @spec minimal_map(map()) :: String.t()
  defp minimal_map(ticket) do
    ticket
    |> convert_time()
    |> Map.values()
    |> Enum.reduce("", fn key, acc ->
      acc <> if is_binary(key), do: "#{key},", else: "#{inspect(key)},"
    end)
  end

  @spec convert_time(map()) :: map()
  defp convert_time(ticket) do
    ticket
    |> Map.put(:inserted_at, Timex.format!(ticket.inserted_at, "{YYYY}-{0M}-{0D}"))
  end

  @doc """
  Updating tickets in bulk
  """
  @spec update_bulk_ticket(map()) :: boolean
  def update_bulk_ticket(params) do
    update_ids = params |> Map.get(:update_ids, [])

    tickets = Repo.all(from(t in Ticket, where: t.id in ^update_ids))

    _result =
      Enum.reduce(tickets, :ok, fn ticket, _acc ->
        update_ticket(ticket, params)
      end)

    true
  end
end
