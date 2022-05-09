defmodule Glific.AccessControl.Permission do
  @moduledoc """
  The minimal wrapper for the base Access Control Permission structure
  """
  use Ecto.Schema

  alias Glific.AccessControl.Role

  alias __MODULE__
  import Ecto.Changeset

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          entity: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }
  schema "permissions" do
    field :entity, :string
    many_to_many :roles, Role, join_through: "role_permissions", on_replace: :delete
    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Permission.t(), map()) :: Ecto.Changeset.t()
  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:entity])
    |> validate_required([:entity])
  end
end
