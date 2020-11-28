defmodule Glific.Templates.Translations do
  @moduledoc false

  use Ecto.Schema

  @type t() :: %__MODULE__{
          body: String.t() | nil,
          language_id: String.t() | nil,
          status: String.t() | nil,
          channel: map() | nil
        }

  embedded_schema do
    field :body, :string
    field :language_id, :string
    field :status, :string
    field :channel, :map
  end

end
