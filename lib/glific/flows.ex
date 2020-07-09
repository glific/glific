defmodule Glific.Flows do
  @moduledoc """
  The Flows context.
  """

  import Ecto.Query, warn: false
  alias Glific.Repo

  alias Glific.Flows.Flow
  alias Glific.Flows.FlowRevision

  @doc """
  Returns the list of flows.

  ## Examples

      iex> list_flows()
      [%Flow{}, ...]

  """
  def list_flows do
    Repo.all(Flow)
  end

  @doc """
  Gets a single flow.

  Raises `Ecto.NoResultsError` if the Flow does not exist.

  ## Examples

      iex> get_flow!(123)
      %Flow{}

      iex> get_flow!(456)
      ** (Ecto.NoResultsError)

  """
  def get_flow!(id), do: Repo.get!(Flow, id)

  @doc """
  Creates a flow.

  ## Examples

      iex> create_flow(%{field: value})
      {:ok, %Flow{}}

      iex> create_flow(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_flow(attrs \\ %{}) do
    %Flow{}
    |> Flow.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a flow.

  ## Examples

      iex> update_flow(flow, %{field: new_value})
      {:ok, %Flow{}}

      iex> update_flow(flow, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_flow(%Flow{} = flow, attrs) do
    flow
    |> Flow.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a flow.

  ## Examples

      iex> delete_flow(flow)
      {:ok, %Flow{}}

      iex> delete_flow(flow)
      {:error, %Ecto.Changeset{}}

  """
  def delete_flow(%Flow{} = flow) do
    Repo.delete(flow)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flow changes.

  ## Examples

      iex> change_flow(flow)
      %Ecto.Changeset{data: %Flow{}}

  """
  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.changeset(flow, attrs)
  end

  def get_flow_revision_list(flow_uuid) do
    flow = get_flow_with_revision(flow_uuid)
    user = %{email: "pankaj@glific.com", name: "Pankaj Agrawal"}

    assetList =
      Enum.reduce(flow.revisions, [], fn revision, acc ->
          acc = [ %{ user: user, created_on: revision.inserted_at, id: revision.id, version: "13.0.0", revision: revision.revision_number} | acc]
      end)

    %{ results:  assetList}
  end

  def get_flow_revision(flow_uuid, revision_number) do
    flow = get_flow_with_revision(flow_uuid)
    {revision_number, ""} = Integer.parse(revision_number)

    revision = Enum.at(flow.revisions, revision_number - 1)
    %{ definition: revision.definition, metadata: %{ issues: [] } }
  end

   defp get_flow_with_revision(flow_uuid) do
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: flow_uuid})
    Repo.preload(flow, :revisions)
  end

  def create_flow_revision(definition) do
    uuid = definition["uuid"]
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: uuid})

    flow =  Repo.preload(flow, :revisions)

    attrs = %{
      definition: definition,
      flow_id: flow.id,
      revision_number: length(flow.revisions) + 1
    }

    %FlowRevision{}
    |> FlowRevision.changeset(attrs)
    |> Repo.insert()

  end
end
