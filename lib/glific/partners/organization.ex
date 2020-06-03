defmodule Glific.Partners.Organization do
  @moduledoc """
  Organizations are the group of users who will access the system
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.Partners.BSP

  # define all the required fields for organization
  @required_fields [:name, :contact_name, :email, :bsp_id, :bsp_key, :wa_number]

  # define all the optional fields for organization
  @optional_fields []

  @type t() :: %__MODULE__{
          id: non_neg_integer | nil,
          name: String.t() | nil,
          contact_name: String.t() | nil,
          email: String.t() | nil,
          bsp_id: non_neg_integer | nil,
          bsp: BSP.t() | Ecto.Association.NotLoaded.t() | nil,
          bsp_key: String.t() | nil,
          wa_number: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "organizations" do
    field :name, :string
    field :contact_name, :string
    field :email, :string
    field :wa_number, :string
    field :bsp_key, :string
    belongs_to :bsp, BSP

    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(Organization.t(), map()) :: Ecto.Changeset.t()
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:email)
    |> unique_constraint(:wa_number)
  end
end
