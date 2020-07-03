defmodule Glific.Flows.Wait do
  @moduledoc """
  The Wait object which encapsulates one wait in a given router.
  """
  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Flows.Router

  @required_fields [:router_uuid]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          type: String.t() | nil,
          router_uuid: Ecto.UUID.t() | nil,
          router: Router.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "waits" do
    field :type, :string

    belongs_to :router, Router, foreign_key: :router_uuid, references: :uuid, primary_key: true
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Wait.t(), map()) :: Ecto.Changeset.t()
  def changeset(wait, attrs) do
    wait
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:router_uuid)
  end
end
