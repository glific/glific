defmodule Glific.Flows.Localization do
  @moduledoc """
  The Localization object which stores all the localizations for all
  languages for a flow
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields []
  @optional_fields [:localizations]

  @type t() :: %__MODULE__{
          localizations: map() | nil
        }

  embedded_schema do
    field :localizations, :map
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Exit.t(), map()) :: Ecto.Changeset.t()
  def changeset(exit, attrs) do
    exit
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map()) :: Localization.t()
  def process(json) do
    %Localization{
      localizations:
        json
        |> Enum.reduce(
          %{},
          fn {language, translations}, acc ->
            Map.put(
              acc,
              language,
              Enum.reduce(
                %{},
                translations,
                fn {uuid, values}, acc ->
                  Map.put(acc, uuid, hd(values["text"]))
                end
              )
            )
          end
        )
    }
  end
end
