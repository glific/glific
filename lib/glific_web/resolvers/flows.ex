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

  @doc """
  Get a specific flow by id
  """
  @spec flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def flow(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}),
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
  def create_flow(_, %{input: params}, _) do
    with {:ok, flow} <- Flows.create_flow(params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc false
  @spec update_flow(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_flow(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}),
         {:ok, flow} <- Flows.update_flow(flow, params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc false
  @spec delete_flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_flow(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}),
         {:ok, flow} <- Flows.delete_flow(flow) do
      {:ok, flow}
    end
  end

  @doc """
  Publish a flow
  """
  @spec publish_flow(Absinthe.Resolution.t(), %{uuid: String.t()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def publish_flow(_, %{uuid: uuid}, _) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{uuid: uuid}),
         {:ok, _flow} <- Flows.publish_flow(flow) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Start a flow for a contact
  """
  @spec start_contact_flow(Absinthe.Resolution.t(), %{flow_id: integer, contact_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def start_contact_flow(_, %{flow_id: flow_id, contact_id: contact_id}, %{
        context: %{current_user: user}
      }) do
    with {:ok, flow} <-
           Repo.fetch_by(Flow, %{id: flow_id, organization_id: user.organization_id}),
         {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: user.organization_id}),
         {:ok, _flow} <- Flows.start_contact_flow(flow, contact) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Start a flow for all contacts of a group
  """
  @spec start_group_flow(Absinthe.Resolution.t(), %{flow_id: integer, group_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def start_group_flow(_, %{flow_id: flow_id, group_id: group_id}, %{
        context: %{current_user: user}
      }) do
    with {:ok, flow} <-
           Repo.fetch_by(Flow, %{id: flow_id, organization_id: user.organization_id}),
         {:ok, group} <-
           Repo.fetch_by(Group, %{id: group_id, organization_id: user.organization_id}),
         {:ok, _flow} <- Flows.start_group_flow(flow, group) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Make a copy a flow
  """
  @spec copy_flow(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def copy_flow(_, %{id: id, input: params}, %{
        context: %{current_user: user}
      }) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}),
         {:ok, flow} <- Flows.copy_flow(flow, params) do
      {:ok, %{flow: flow}}
    end
  end
end
