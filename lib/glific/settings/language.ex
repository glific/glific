defmodule Glific.Settings.Language do
  @moduledoc """
  Ecto schema and minimal interface for the languages table
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Settings.Language

  @required_fields [:label, :label_locale, :locale]
  @optional_fields [:description, :is_active]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          label_locale: String.t() | nil,
          locale: String.t() | nil,
          description: String.t() | nil,
          is_active: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "languages" do
    field :label, :string
    field :label_locale, :string
    field :locale, :string
    field :description, :string

    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(Language.t(), map()) :: Ecto.Changeset.t()
  def changeset(language, attrs) do
    language
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :locale])
    |> foreign_key_constraint(:tags)
  end

  @doc """
  Delete changeset pattern we use for all data types
  """
  @spec delete_changeset(Language.t()) :: Ecto.Changeset.t()
  def delete_changeset(language) do
    language
    |> cast(%{}, @required_fields ++ @optional_fields)
    |> foreign_key_constraint(:tags_language_id_fkey, name: :tags_language_id_fkey)
  end
end
