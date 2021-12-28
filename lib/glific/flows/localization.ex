defmodule Glific.Flows.Localization do
  @moduledoc """
  The Localization object which stores all the localizations for all
  languages for a flow
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows.Action,
    Flows.Case,
    Flows.Category,
    Flows.FlowContext,
    Settings
  }

  @type t() :: %__MODULE__{
          localizations: map() | nil
        }

  embedded_schema do
    field :localizations, :map
  end

  @spec add_text(map(), map()) :: map()
  defp add_text(map, values) do
    if is_nil(values["text"]) do
      map
    else
      Map.put(map, :text, hd(values["text"]))
    end
  end

  @spec add_attachments(map(), map()) :: map()
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

  @spec add_case_arguments(map(), map()) :: map()
  defp add_case_arguments(map, values) do
    if values["arguments"] in [[""], nil, []],
      do: map,
      else: Map.put(map, :arguments, values["arguments"])
  end

  @spec add_category_name(map(), map()) :: map()
  defp add_category_name(map, values) do
    if values["name"] in ["", nil, []],
      do: map,
      else: Map.put(map, :name, values["name"])
  end

  @spec add_template_variables(map(), map()) :: map()
  defp add_template_variables(map, values) do
    if values["variables"] in ["", nil, []],
      do: map,
      else: Map.put(map, :variables, values["variables"])
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
        # We need to think about a better way to do this checking.
        # For now, we are just going to check based on the keys in the translations
        map =
          %{}
          |> add_text(values)
          |> add_attachments(values)
          |> add_case_arguments(values)
          |> add_category_name(values)
          |> add_template_variables(values)

        if values == %{}, do: acc, else: Map.put(acc, uuid, map)
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

    element =
      context
      |> load_localizations()
      |> translated_element(language_id, action.uuid, action)

    # in some cases we have a localization field, but either the text or the attachment
    # is missing and does not have values, in which case, we switch to using the default
    # text or attachment from action
    if type == :text,
      do: Map.get(element, :text, action.text),
      else: Map.get(element, :attachments, action.attachments)
  end

  @doc """
  Given a language id and an case uuid, return the translation if
  one exists, else return the original text
  """
  @spec get_translated_case_arguments(FlowContext.t(), Case.t()) :: list() | nil
  def get_translated_case_arguments(context, flow_case) do
    language_id = context.contact.language_id

    context
    |> load_localizations()
    |> translated_element(language_id, flow_case.uuid)
    |> Map.get(:arguments, flow_case.arguments)
  end

  @doc """
  Given a language id and an category uuid, return the translation if
  one exists, else return the original text
  """
  @spec get_translated_category_name(FlowContext.t(), Category.t()) :: String.t() | nil
  def get_translated_category_name(context, category) do
    language_id = context.contact.language_id

    context
    |> load_localizations()
    |> translated_element(language_id, category.uuid)
    |> Map.get(:name, category.name)
  end

  @doc """
  Given a language id and an template uuid, return the variable translation if
  one exists, else return the original variable
  """
  @spec get_translated_template_vars(
          FlowContext.t(),
          atom | %{:uuid => binary, :variables => any, optional(any) => any}
        ) :: list() | nil
  def get_translated_template_vars(context, template) do
    language_id = context.contact.language_id

    context
    |> load_localizations()
    |> translated_element(language_id, template.uuid)
    |> Map.get(:variables, template.variables)
  end

  @spec load_localizations(FlowContext.t()) :: map()
  defp load_localizations(context) do
    if Ecto.assoc_loaded?(context.flow) and
         context.flow.localization != nil,
       do: context.flow.localization.localizations,
       else: %{}
  end

  @spec translated_element(map(), integer(), String.t(), Action.t() | map()) :: Action.t() | map()
  defp translated_element(localization, language_id, uuid, default \\ %{}) do
    if Map.has_key?(localization, language_id) and
         Map.has_key?(Map.get(localization, language_id), uuid) do
      Map.get(Map.get(localization, language_id), uuid)
    else
      default
    end
  end
end
