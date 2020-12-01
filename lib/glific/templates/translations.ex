defmodule Glific.Templates.Translations do
  @moduledoc """
  A pipe for managing the translations
  """

  use Ecto.Schema

  @optional_fields [:body, :language_id, :number_parameters]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          body: String.t() | nil,
          language_id: non_neg_integer | nil,
          number_parameters: non_neg_integer | nil,
        }

  schema "translations" do
    field :body, :string
    field :language_id, :integer
    field :number_parameters, :integer
  end
end
