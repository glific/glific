defmodule Glific.Partners.OrganizationCredential do
  @moduledoc """
  Organization's credentials
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Glific.Partners.Organization

  @required_fields [:organization_id]
  @optional_fields [:regular_keys, :secret_keys]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          shortcode: String.t() | nil,
          regular_keys: map() | nil,
          secret_keys: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "organization_credentials" do
    field :shortcode, :string
    field :regular_keys, :map
    field :secret_keys, :map

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(OrganizationCredential.t(), map()) :: Ecto.Changeset.t()
  def changeset(search, attrs) do
    search
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:shortcode, :organization_id])
  end
end
