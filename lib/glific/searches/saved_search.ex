defmodule Glific.Searches.SavedSearch do
  @moduledoc """
  The minimal wrapper for the base Saved Search structure
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Glific.Partners.Organization

  @required_fields [:label, :shortcode, :args, :organization_id]
  @optional_fields [:is_reserved]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          shortcode: String.t() | nil,
          args: map() | nil,
          is_reserved: boolean(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "saved_searches" do
    field :args, :map
    field :label, :string
    field :shortcode, :string
    field :is_reserved, :boolean, default: false

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(SavedSearch.t(), map()) :: Ecto.Changeset.t()
  def changeset(search, attrs) do
    search
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:shortcode])
  end
end
