defmodule Glific.Flows.Case do
  @moduledoc """
  The Case object which encapsulates one category in a given node.
  """

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    Category,
    Router,
  }

  @required_fields [:type, :arguments, :category_id, :router_id]
  @optional_fields []

  @type t() :: %__MODULE__{
    __meta__: Ecto.Schema.Metadata.t(),
    uuid: Ecto.UUID.t() | nil,

    type: FlowCaseEnum | nil,
    arguments: List()

    category_id: Ecto.UUID.t() | nil,
    category: Category.t() | Ecto.Association.NotLoaded.t() | nil,

    router_id: Ecto.UUID.t() | nil,
    router: Router.t() | Ecto.Association.NotLoaded.t() | nil,
  }

  schema "cases" do
    field :name, :string

    has_one :category, Category

    belongs_to :router, Router
  end


  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Router.t(), map()) :: Ecto.Changeset.t()
  def changeset(Router, attrs) do
    tag
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:router_id)
    |> foreign_key_constraint(:destination_router_id)
  end


end
