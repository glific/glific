defmodule Glific.Partners.Credential do
  @moduledoc """
  Organization's credentials
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Glific.Partners.Organization

  @required_fields []
  @optional_fields [:shortcode, :keys, :secrets, :organization_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          shortcode: String.t() | nil,
          keys: map() | nil,
          secrets: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "credentials" do
    field :shortcode, :string
    field :keys, :map
    field :secrets, :map

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Credential.t(), map()) :: Ecto.Changeset.t()
  def changeset(search, attrs) do
    search
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:shortcode, :organization_id])
  end
end
