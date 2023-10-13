defmodule GlificWeb.Resolvers.Tickets do
  @moduledoc """
  Ticket Resolver which sits between the GraphQL schema and Glific Ticket Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """
  alias Glific.{
    Repo,
    Tickets,
    Tickets.Ticket
  }

  @doc """
  Get a specific ticket by id
  """
  @spec ticket(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def ticket(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, ticket} <- Repo.fetch_by(Ticket, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{ticket: ticket}}
  end

  @doc """
  Get the list of tickets
  """
  @spec tickets(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Ticket]}
  def tickets(_, args, _) do
    {:ok, Tickets.list_tickets(args)}
  end

  @doc """
  Get the count of tickets filtered by args
  """
  @spec count_tickets(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_tickets(_, args, _) do
    {:ok, Tickets.count_tickets(args)}
  end

  @doc false
  @spec create_ticket(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_ticket(_, %{input: params}, _) do
    with {:ok, ticket} <- Tickets.create_ticket(params) do
      {:ok, %{ticket: ticket}}
    end
  end

  @doc false
  @spec update_ticket(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_ticket(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, ticket} <- Repo.fetch_by(Ticket, %{id: id, organization_id: user.organization_id}),
         {:ok, ticket} <- Tickets.update_ticket(ticket, params) do
      {:ok, %{ticket: ticket}}
    end
  end

  @doc false
  @spec delete_ticket(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_ticket(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, ticket} <- Repo.fetch_by(Ticket, %{id: id, organization_id: user.organization_id}) do
      Tickets.delete_ticket(ticket)
    end
  end

  @doc """
  Fetches support tickets between start_date and end_date
  """
  @spec fetch_support_tickets(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, String.t()}
  def fetch_support_tickets(_, args, _) do
    {:ok, Tickets.fetch_support_tickets(args)}
  end

  @doc false
  @spec update_ticket(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_bulk_ticket(_, %{input: params}, _) do
    with {:ok, ticket} <- Tickets.update_bulk_ticket(params) do
      {:ok, %{ticket: ticket}}
    end
  end
end
