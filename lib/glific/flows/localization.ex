defmodule Glific.Flows.Localization do
  @moduledoc """
  The Localization object which stores all the localizations for all
  languages for a flow
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows.Action,
    Flows.FlowContext,
    Settings
  }

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
  def process(json) when is_nil(json) do
    language_map = Settings.locale_id_map()
    %Localization{localizations: language_map}
  end

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

  @doc """
  Given a language id and an action uuid, return the translation if
  one exists, else return the original text
  """
  @spec get_translation(FlowContext.t(), Action.t()) :: String.t()
  def get_translation(context, action) do
    language_id = context.contact.language_id

    localization =
      if Ecto.assoc_loaded?(context.flow) and
           Ecto.assoc_loaded?(context.flow.localization),
         do: context.flow.localization.localizations,
         else: %{}

    if Map.has_key?(localization, language_id) and
         Map.has_key?(Map.get(localization, language_id), action.uuid),
       do: Map.get(Map.get(localization, language_id), action.uuid),
       else: action.text
  end
end
