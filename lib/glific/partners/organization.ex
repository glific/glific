defmodule Glific.Partners.Organization do
  @moduledoc """
  Organizations are the group of users who will access the system
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Partners.BSP

  # define all the required fields for organization
  @required_fields [
    :name,
    :contact_name,
    :email,
    :bsp_id,
    :bsp_key,
    :wa_number
  ]

  # define all the optional fields for organization
  @optional_fields []

  schema "organizations" do
    field :name, :string
    field :contact_name, :string
    field :email, :string
    field :wa_number, :string
    field :bsp_key, :string
    belongs_to :bsp, BSP

    timestamps()
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
