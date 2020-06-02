defmodule Glific.Partners.BSP do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  The BSP schema.
  """

  # define all the required fields for bsp
  @required_fields [
    :name,
    :url,
    :api_end_point
  ]

  # define all the optional fields for bsp
  @optional_fields []

  schema "bsps" do
    field(:api_end_point, :string)
    field(:name, :string)
    field(:url, :string)

    timestamps()
  end

  @doc false
  def changeset(bsp, attrs) do
    bsp
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
