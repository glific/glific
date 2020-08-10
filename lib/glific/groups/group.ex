defmodule Glific.Groups.Group do
  @moduledoc """
  The minimal wrapper for the base Group structure
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Glific.Groups.Group

  @required_fields [:label]
  @optional_fields [:is_restricted]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          is_restricted: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "groups" do
    field :label, :string
    field :is_restricted, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Group.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:label)
  end
end
