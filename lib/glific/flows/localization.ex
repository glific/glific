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

  defp add_text(map, values) do
    if is_nil(values["text"]) do
      map
    else
      Map.put(map, :text, hd(values["text"]))
    end
  end

  defp add_attachments(map, values) do
    cond do
      is_nil(values["attachments"]) ->
        map

      values["attachments"] == [] ->
        map

      not is_list(values["attachments"]) ->
        map

      is_nil(hd(values["attachments"])) ->
        map

      true ->
        case String.split(hd(values["attachments"]), ":", parts: 2) do
          [type, url] -> Map.put(map, :attachments, %{type => url})
          _ -> map
        end
    end
  end

  # given a json snippet containing all the translation for a specific language
  # store them in a uuid map
  @spec process_translation(map()) :: map()
  defp process_translation(json) when is_nil(json), do: %{}

  defp process_translation(json) do
    Enum.reduce(
      json,
      %{},
      fn {uuid, values}, acc ->
        if is_nil(values["text"]) and is_nil(values["attachments"]) do
          acc
        else
          map = %{} |> add_text(values) |> add_attachments(values)
          Map.put(acc, uuid, map)
        end
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
  @spec get_translation(FlowContext.t(), Action.t(), atom()) :: String.t() | nil | map()
  def get_translation(context, action, type \\ :text) do
    language_id = context.contact.language_id

    localization =
      if Ecto.assoc_loaded?(context.flow) and
           context.flow.localization != nil,
         do: context.flow.localization.localizations,
         else: %{}

    element =
      if Map.has_key?(localization, language_id) and
           Map.has_key?(Map.get(localization, language_id), action.uuid) do
        Map.get(Map.get(localization, language_id), action.uuid)
      else
        action
      end

    # in some cases we have a localization field, but either the text or the attachment
    # is missing and does not have values, in which case, we switch to using the default
    # text or attachment from action
    if type == :text,
      do: Map.get(element, :text, action.text),
      else: Map.get(element, :attachments, action.attachments)
  end
end
