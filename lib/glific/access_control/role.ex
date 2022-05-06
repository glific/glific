defmodule Glific.AccessControl.Role do
  use Ecto.Schema
  import Ecto.Changeset

  schema "roles" do
    field :description, :string
    field :is_reserved, :boolean, default: false
    field :label, :string

    timestamps()
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:label, :description, :is_reserved])
    |> validate_required([:label, :description, :is_reserved])
  end
end
