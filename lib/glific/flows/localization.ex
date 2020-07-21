defmodule Glific.Flows.Localization do
  @moduledoc """
  The Localization object which stores all the localizations for all
  languages for a flow
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.Settings

  @type t() :: %__MODULE__{
          localizations: map() | nil
        }

  embedded_schema do
    field :localizations, :map
  end

  # given a json snippet containing all the translation for a specific language
  # store them in a uuid map
  @spec process_translation(map()) :: map()
  defp process_translation(json) do
    Enum.reduce(
      json,
      %{},
      fn {uuid, values}, acc ->
        Map.put(acc, uuid, hd(values["text"]))
      end
    )
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map()) :: Localization.t()
  def process(json) do
    language_map = Settings.locale_id_map()
    %Localization{
      localizations:
        json
        |> Enum.reduce(
          %{},
          fn {language, translations}, acc ->
            translated = process_translation(translations)
            acc
            |> Map.put(language, translated)
            |> Map.put(language_map[language], translated)
          end
        )
    }
  end
end
