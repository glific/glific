defmodule GlificWeb.Resolvers.Flows do
  @moduledoc """
  Flow Resolver which sits between the GraphQL schema and Glific Flow Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Contacts.Contact,
    Flows,
    Flows.Flow,
    Groups.Group,
    Repo
  }

  alias GlificWeb.Resolvers.Helper

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
  def flows(_, args, context) do
    {:ok, Flows.list_flows(Helper.add_org_filter(args, context))}
  end

  @doc """
  Get the count of flows filtered by args
  """
  @spec count_flows(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_flows(_, args, context) do
    {:ok, Flows.count_flows(Helper.add_org_filter(args, context))}
  end

  @doc false
  @spec create_flow(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_flow(_, %{input: params}, _) do
    with {:ok, flow} <- Flows.create_flow(params) do
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

  @doc false
  @spec start_contact_flow(Absinthe.Resolution.t(), %{flow_id: integer, contact_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def start_contact_flow(_, %{flow_id: flow_id, contact_id: contact_id}, _) do
    with {:ok, flow} <- Repo.fetch(Flow, flow_id),
         {:ok, contact} <- Repo.fetch(Contact, contact_id),
         {:ok, _flow} <- Flows.start_contact_flow(flow, contact) do
      {:ok, %{success: true}}
    end
  end

  @doc false
  @spec start_group_flow(Absinthe.Resolution.t(), %{flow_id: integer, group_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def start_group_flow(_, %{flow_id: flow_id, group_id: group_id}, _) do
    with {:ok, flow} <- Repo.fetch(Flow, flow_id),
         {:ok, group} <- Repo.fetch(Group, group_id),
         {:ok, _flow} <- Flows.start_group_flow(flow, group) do
      {:ok, %{success: true}}
    end
  end
end
