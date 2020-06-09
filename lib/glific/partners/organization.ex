defmodule Glific.Partners.Organization do
  @moduledoc """
  Organizations are the group of users who will access the system
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.Partners.Provider

  # define all the required fields for organization
  @required_fields [
    :name,
    :display_name,
    :contact_name,
    :email,
    :provider_id,
    :provider_key,
    :provider_number
  ]

  # define all the optional fields for organization
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          display_name: String.t() | nil,
          contact_name: String.t() | nil,
          email: String.t() | nil,
          provider_id: non_neg_integer | nil,
          provider: Provider.t() | Ecto.Association.NotLoaded.t() | nil,
          provider_key: String.t() | nil,
          provider_number: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "organizations" do
    field :name, :string
    field :display_name, :string
    field :contact_name, :string
    field :email, :string
    field :provider_number, :string
    field :provider_key, :string
    belongs_to :provider, Provider

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
    |> unique_constraint(:name)
    |> unique_constraint(:email)
    |> unique_constraint(:provider_number)
  end
end
