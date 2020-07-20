defmodule Glific.Flows.Localization do
  @moduledoc """
  The Localization object which stores all the localizations for all
  languages for a flow
  """
  alias __MODULE__

  use Ecto.Schema

  @type t() :: %__MODULE__{
          localizations: map() | nil
        }

  embedded_schema do
    field :localizations, :map
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map()) :: Localization.t()
  def process(json) do
    value =
      json
      |> Enum.reduce(
        %{},
        fn {language, translations}, acc ->
          Map.put(
            acc,
            language,
            Enum.reduce(
              translations,
              %{},
              fn {uuid, values}, acc ->
                Map.put(acc, uuid, hd(Map.get(values, "text")))
              end
            )
          )
        end
      )

    %Localization{localizations: value}
  end
end
