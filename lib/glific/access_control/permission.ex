defmodule Glific.AccessControl.Permission do
  use Ecto.Schema
  import Ecto.Changeset

  schema "permissions" do
    field :entity, :string

    timestamps()
  end

  @doc false
  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:entity])
    |> validate_required([:entity])
  end
end
