defmodule Glific.Settings.Language do
  @moduledoc """
  Ecto schema and minimal interface for the languages table
  """

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:label, :locale]
  @optional_fields [:description, :is_active]

  schema "languages" do
    field :label, :string
    field :locale, :string
    field :description, :string

    field :is_active, :boolean, default: false

    # Comment for now, enable when we add tags to glific
    # has_many :tags, Glific.Attributes.Tag

    timestamps()
  end

  @doc false
  def changeset(language, attrs) do
    language
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:label)
    |> unique_constraint(:locale)
  end
end
