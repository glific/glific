defmodule GlificWeb.Resolvers.Flows do
  @moduledoc """
  Flow Resolver which sits between the GraphQL schema and Glific Flow Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Flows,
    Flows.Flow,
    Repo
  }

  @doc """
  Get a specific flow by id
  """
  @spec flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def flow(_, %{id: id}, _) do
    with {:ok, flow} <- Repo.fetch(Flow, id),
         do: {:ok, %{flow: flow}}
  end

  @doc """
  Get the list of flows
  """
  @spec flows(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Flow]}
  def flows(_, args, _) do
    {:ok, Flows.list_flows(args)}
  end

  @doc """
  Get the count of flows filtered by args
  """
  @spec count_flows(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_flows(_, args, _) do
    {:ok, Flows.count_flows(args)}
  end

  @doc false
  @spec create_flow(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_flow(_, %{input: params}, %{context: %{current_user: current_user}}) do
    with params <- Map.put_new(params, :organization_id, current_user.organization_id ),
      {:ok, flow} <- Flows.create_flow(params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc false
  @spec update_flow(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_flow(_, %{id: id, input: params}, _) do
    with {:ok, flow} <- Repo.fetch(Flow, id),
         {:ok, flow} <- Flows.update_flow(flow, params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc false
  @spec delete_flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_flow(_, %{id: id}, _) do
    with {:ok, flow} <- Repo.fetch(Flow, id),
         {:ok, flow} <- Flows.delete_flow(flow) do
      {:ok, flow}
    end
  end

  @doc false
  @spec publish_flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def publish_flow(_, %{id: id}, _) do
    with {:ok, flow} <- Repo.fetch(Flow, id),
         {:ok, _flow} <- Flows.publish_flow(flow) do
      {:ok, %{success: true}}
    end
  end
end
