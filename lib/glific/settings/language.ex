defmodule Glific.Settings.Language do
  use Ecto.Schema
  import Ecto.Changeset

  schema "languages" do
    field :description, :string
    field :is_active, :boolean, default: false
    field :label, :string
    field :locale, :string

    # has_many :tags, Glific.Attributes.Tag

    timestamps()
  end

  @doc false
  def changeset(language, attrs) do
    language
    |> cast(attrs, [:label, :description, :locale, :is_active])
    |> validate_required([:label, :locale])
    |> unique_constraint(:label)
    |> unique_constraint(:locale)
  end
end
