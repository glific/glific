defmodule GlificWeb.Resolvers.FlowLabels do
  @moduledoc """
  Flow Labels Resolver which sits between the GraphQL schema and Glific Flow Label Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """
  alias Glific.{
    Flows.FlowLabel,
    Repo
  }

  @doc """
  Get a specific flow label by id
  """
  @spec flow_label(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def flow_label(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, flow_label} <-
           Repo.fetch_by(FlowLabel, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{flow_label: flow_label}}
  end

  @doc """
  Get the list of flow labels
  """
  @spec flow_labels(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [FlowLabel]}
  def flow_labels(_, args, _) do
    {:ok, FlowLabel.list_flow_labels(args)}
  end

  @doc """
  Get the count of flow labels filtered by args
  """
  @spec count_flow_labels(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_flow_labels(_, args, _) do
    {:ok, FlowLabel.count_flow_labels(args)}
  end
end
