defmodule Glific.Flows.Wait do
  @moduledoc """
  The Wait object which encapsulates one wait in a given router.
  """

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.Router

  @required_fields [:router_id, :destination_router_id]
  @optional_fields []

  @type t() :: %__MODULE__{
    __meta__: Ecto.Schema.Metadata.t(),
    uuid: Ecto.UUID.t() | nil,

    type: String.t() | nil,

    router_id: Ecto.UUID.t() | nil,
    router: Router.t() | Ecto.Association.NotLoaded.t() | nil,
  }

  schema "waits" do
    field :type, :string

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
  end


end
