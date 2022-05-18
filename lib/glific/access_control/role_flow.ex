defmodule Glific.AccessControl.RoleFlow do
  @moduledoc """
  A pipe for managing the role flows
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Flows.Flow,
    AccessControl.Role,
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

  schema "role_flows" do
    belongs_to :role, Role
    belongs_to :flow, Flow
    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(RoleFlow.t(), map()) :: Ecto.Changeset.t()
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
      iex> create_access_control(%{field: value})
      {:ok, %Role{}}
      iex> create_access_control(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_access_control(map()) :: {:ok, RoleFlow.t()} | {:error, Ecto.Changeset.t()}
  def create_access_control(attrs \\ %{}) do
    IO.inspect(attrs)

    %RoleFlow{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  updates
  """
  @spec update_control_access(map()) :: map()
  def update_control_access(
        %{
          entity_id: entity_id,
          add_role_ids: add_role_ids,
          delete_role_ids: delete_role_ids
        } = attrs
      ) do
    access_controls =
      Enum.reduce(
        add_role_ids,
        [],
        fn role_id, acc ->
          case create_access_control(Map.merge(attrs, %{role_id: role_id, flow_id: entity_id})) do
            {:ok, access_control} -> [access_control | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = delete_access_control_by_role_ids(entity_id, delete_role_ids)

    %{
      number_deleted: number_deleted,
      access_controls: access_controls
    }
  end

  @doc """
  Delete group contacts
  """
  @spec delete_access_control_by_role_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_access_control_by_role_ids(entity_id, role_ids) do
    fields = {{:flow_id, entity_id}, {:role_id, role_ids}}
    Repo.delete_relationships_by_ids(RoleFlow, fields)
  end
end
