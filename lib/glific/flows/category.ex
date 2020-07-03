defmodule Glific.Flows.Category do
  @moduledoc """
  The Category object which encapsulates one category in a given node.
  """

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    Exit,
    Router,
  }

  @required_fields [:name, :exit_id, :router_id]
  @optional_fields []

  @type t() :: %__MODULE__{
    __meta__: Ecto.Schema.Metadata.t(),
    uuid: Ecto.UUID.t() | nil,

    name: String.t() | nil,

    exit_id: Ecto.UUID.t() | nil,
    exit: Exit.t() | Ecto.Association.NotLoaded.t() | nil,

    router_id: Ecto.UUID.t() | nil,
    router: Router.t() | Ecto.Association.NotLoaded.t() | nil,
  }

  schema "categories" do
    field :name, :string

    has_one :exit, Exit
    has_many :cases, Case

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
