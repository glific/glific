defmodule Glific.Searches.SavedSearch do
  @moduledoc """
  The minimal wrapper for the base Saved Search structure
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  @required_fields [:label, :args]
  @optional_fields [:is_reserved]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          args: map() | nil,
          is_reserved: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "saved_searches" do
    field :args, :map
    field :label, :string
    field :is_reserved, :boolean, default: false

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
    |> unique_constraint([:label])
  end
end
