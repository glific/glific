defmodule Glific.Templates.Translations do
  @moduledoc false
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [
    :body,
    :language_id,
    :status,
    :channel
  ]

  @type t() :: %__MODULE__{
          body: String.t() | nil,
          language_id: integer | nil,
          status: String.t() | nil,
          channel: map() | nil
        }

  embedded_schema do
    field :body, :string
    field :language_id, :integer
    field :status, :string
    field :channel, :map
  end

  @doc """
  Changeset pattern for translations
  """
  @spec translations_changeset(Translations.t(), map()) :: Ecto.Changeset.t()
  def translations_changeset(translations, attrs) do
    translations
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
