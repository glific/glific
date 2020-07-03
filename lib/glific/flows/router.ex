defmodule Glific.Flows.Router do
  @moduledoc """
  The Router object which encapsulates the router in a given node.
  """
  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    Case,
    Category,
    Node
  }

  @required_fields [:type, :operand, :default_category_uuid, :node_uuid]
  @optional_fields [:result_name, :wait_type]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          type: String.t() | nil,
          wait_type: String.t() | nil,
          default_category_uuid: Ecto.UUID.t() | nil,
          default_category: Category.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "routers" do
    field :type, :string
    field :operand, :string
    field :result_name, :string
    field :wait_type, :string

    has_many :cases, Case
    has_many :categories, Category

    belongs_to :default_category, Category,
      foreign_key: :default_category_uuid,
      references: :uuid,
      primary_key: true

    belongs_to :node, Node, foreign_key: :node_uuid, references: :uuid, primary_key: true
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Router.t(), map()) :: Ecto.Changeset.t()
  def changeset(router, attrs) do
    router
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:node_uuid)
    |> foreign_key_constraint(:default_category_uuid)
  end
end
