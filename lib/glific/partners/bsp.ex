defmodule Glific.Partners.BSP do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bsps" do
    field :api_end_point, :string
    field :name, :string
    field :url, :string

    timestamps()
  end

  @doc false
  def changeset(bsp, attrs) do
    bsp
    |> cast(attrs, [:name, :url, :api_end_point])
    |> validate_required([:name, :url, :api_end_point])
  end
end
