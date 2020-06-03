defmodule Glific.Partners.BSP do
  @moduledoc """
  The wrapper for BSP.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # define all the required fields for bsp
  @required_fields [
    :name,
    :url,
    :api_end_point
  ]

  # define all the optional fields for bsp
  @optional_fields []

  schema "bsps" do
    field :name, :string
    field :url, :string
    field :api_end_point, :string

    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(%Glific.Partners.BSP{}, map()) :: Ecto.Changeset.t()
  def changeset(bsp, attrs) do
    bsp
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
