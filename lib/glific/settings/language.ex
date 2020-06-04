defmodule Glific.Settings.Language do
  @moduledoc """
  Ecto schema and minimal interface for the languages table
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Settings.Language

  @required_fields [:label, :locale]
  @optional_fields [:description, :is_active]

  @type t() :: %__MODULE__{
          id: non_neg_integer | nil,
          label: String.t() | nil,
          locale: String.t() | nil,
          description: String.t() | nil,
          is_active: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "languages" do
    field :label, :string
    field :locale, :string
    field :description, :string

    field :is_active, :boolean, default: false

    # Comment for now, enable when we add tags to glific
    # has_many :tags, Glific.Attributes.Tag

    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(Language.t(), map()) :: Ecto.Changeset.t()
  def changeset(language, attrs) do
    language
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:label)
    |> unique_constraint(:locale)
    |> foreign_key_constraint(:tags)
  end
end
