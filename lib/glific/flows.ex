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
  @spec list_flows() :: [Flow.t()]
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
  @spec get_flow!(integer) :: Flow.t()
  def get_flow!(id), do: Repo.get!(Flow, id)

  @doc """
  Creates a flow.

  ## Examples

      iex> create_flow(%{field: value})
      {:ok, %Flow{}}

      iex> create_flow(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_flow(map()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
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
  @spec update_flow(Flow.t(), map()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
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
  @spec delete_flow(Flow.t()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def delete_flow(%Flow{} = flow) do
    Repo.delete(flow)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flow changes.

  ## Examples

      iex> change_flow(flow)
      %Ecto.Changeset{data: %Flow{}}

  """
  @spec change_flow(Flow.t(), map()) :: Ecto.Changeset.t()
  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.changeset(flow, attrs)
  end

  @doc """
    Get a list of all the revisions based on a flow UUID
  """
  @spec get_flow_revision_list(String.t()) :: %{results: list()}
  def get_flow_revision_list(flow_uuid) do
    flow = get_flow_with_revision(flow_uuid)
    user = %{email: "pankaj@glific.com", name: "Pankaj Agrawal"}

    asset_list =
      Enum.reduce(flow.revisions, [], fn revision, acc ->
        [
          %{
            user: user,
            created_on: revision.inserted_at,
            id: revision.id,
            version: "13.0.0",
            revision: revision.revision_number
          }
          | acc
        ]
      end)

    %{results: asset_list}
  end

  @doc """
    Get specific flow revision by number
  """
  @spec get_flow_revision(String.t(), String.t()) :: map()
  def get_flow_revision(_flow_uuid, revision_id) do
    revision = Repo.get!(FlowRevision, revision_id)
    %{definition: revision.definition, metadata: %{issues: []}}
  end

  # Preload revisions in a flow.
  # We still need to do some refactoring on this approch
  @spec get_flow_with_revision(String.t()) :: Flow.t()
  defp get_flow_with_revision(flow_uuid) do
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: flow_uuid})
    Repo.preload(flow, :revisions)
  end

  @doc """
    Save new revision for the flow
  """
  @spec create_flow_revision(map()) :: FlowRevision.t()
  def create_flow_revision(definition) do
    {:ok, flow} = Repo.fetch_by(Flow, %{uuid: definition["uuid"]})

    flow = Repo.preload(flow, :revisions)

    attrs = %{
      definition: definition,
      flow_id: flow.id,
      revision_number: length(flow.revisions) + 1
    }

    {:ok, revision} =
      %FlowRevision{}
      |> FlowRevision.changeset(attrs)
      |> Repo.insert()

    revision
  end
end
