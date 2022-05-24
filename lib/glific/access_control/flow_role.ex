defmodule Glific.AccessControl.FlowRole do
  @moduledoc """
  A pipe for managing the role flows
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    AccessControl.Role,
    AccessControl.UserRole,
    Flows.Flow,
    Partners.Organization,
    Repo
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:role_id, :flow_id, :organization_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "flow_roles" do
    belongs_to :role, Role
    belongs_to :flow, Flow
    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowRole.t(), map()) :: Ecto.Changeset.t()
  def changeset(role_flow, attrs) do
    role_flow
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(@required_fields)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:flow_id)
  end

  @doc """
  Creates a access control.
  ## Examples
      iex> create_flow_role(%{field: value})
      {:ok, %FlowRole{}}
      iex> create_flow_role(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_flow_role(map()) :: {:ok, FlowRole.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_role(attrs \\ %{}) do
    %FlowRole{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update flow roles based on add_role_ids and delete_role_ids and return number_deleted as integer and roles added as access_controls
  """
  @spec update_flow_roles(map()) :: map()
  def update_flow_roles(
        %{
          flow_id: flow_id,
          add_role_ids: add_role_ids,
          delete_role_ids: delete_role_ids
        } = attrs
      ) do
    access_controls =
      Enum.reduce(
        add_role_ids,
        [],
        fn role_id, acc ->
          case create_flow_role(Map.merge(attrs, %{role_id: role_id, flow_id: flow_id})) do
            {:ok, access_control} -> [access_control | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = delete_flow_roles_by_role_ids(flow_id, delete_role_ids)

    %{
      number_deleted: number_deleted,
      access_controls: access_controls
    }
  end

  @doc """
  Delete flow roles
  """
  @spec delete_flow_roles_by_role_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_flow_roles_by_role_ids(flow_id, role_ids) do
    fields = {{:flow_id, flow_id}, {:role_id, role_ids}}
    Repo.delete_relationships_by_ids(FlowRole, fields)
  end

  @doc """
  Filtering entity object based on user role
  """
  @spec check_access(Ecto.Query.t(), User.t()) :: Ecto.Query.t()
  def check_access(entity_list, user) do
    sub_query =
      FlowRole
      |> select([rf], rf.flow_id)
      |> join(:inner, [rf], ru in UserRole, as: :ru, on: ru.role_id == rf.role_id)
      |> where([rf, ru: ru], ru.user_id == ^user.id)

    entity_list
    |> where(
      [f],
      f.id in subquery(sub_query)
    )
  end
end
