defmodule Glific.Partners.BSP do
  @moduledoc """
  BSP are the third party Business Service providers who will give a access of WhatsApp API
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

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          url: String.t() | nil
        }

  schema "bsps" do
    field :name, :string
    field :url, :string
    field :api_end_point, :string

    has_many :organizations, Glific.Partners.Organization

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
    |> unique_constraint([:name])
    |> foreign_key_constraint(:organizations)
  end

  @doc """
  Delete changeset pattern we use for all data types
  """
  @spec delete_changeset(Organization.t()) :: Ecto.Changeset.t()
  def delete_changeset(organization) do
    organization
    |> cast(%{}, @required_fields ++ @optional_fields)
    |> foreign_key_constraint(:tags_organization_id_fk)
  end
end
