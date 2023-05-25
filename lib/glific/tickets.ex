defmodule Glific.Tickets do
  @moduledoc """
  The Tickets context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Flows.FlowContext,
    Flows.MessageVarParser,
    Messages,
    Repo,
    Tickets.Ticket
  }

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

    %Ticket{}
    |> Ticket.changeset(ticket_params)
    |> Repo.insert()
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
end
