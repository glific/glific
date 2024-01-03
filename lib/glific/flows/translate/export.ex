defmodule Glific.Flows.Translate.Export do
  @moduledoc """
  Lets parse the localization map into a structure that is convenient
  to export out of the json flow and to import back into the json flow
  """

  alias Glific.{
    Flows.Flow,
    Flows.Translate.Import,
    Flows.Translate.Translate,
    Settings
  }

  @doc """
  Export the localization json as a csv structure (list of lists).
  At some point, we might extend this to export it as a .po file
  Lets keep the csv generation very distinct from the extraction
  """
  @spec export_localization(Flow.t()) :: list()
  def export_localization(flow) do
    missing_localization(flow, flow.definition["localization"])
  end

  @doc """
  Do the export and translation and modify the json in one action. Easier for us to debug
  and for smaller NGOs to bypass the review step (not recommended)
  """
  @spec translate(Flow.t()) :: {:ok, any} | {:error, String.t()}
  def translate(flow) do
    flow
    |> export_localization()
    |> Import.import_localization(flow)
  end

  @spec missing_localization(map(), map()) :: list()
  defp missing_localization(flow, all_localization) do
    flow.nodes
    |> Enum.reduce([], fn node, uuids ->
      node.actions
      |> Enum.reduce(uuids, fn action, acc ->
        if action.type == "send_msg" and !action.is_template,
          do: [{action.uuid, action.text} | acc],
          else: acc
      end)
    end)
    |> then(&add_missing_localization(all_localization, &1, flow.organization_id))
  end

  @spec add_missing_localization(map(), list(), non_neg_integer()) :: Keyword.t()
  defp add_missing_localization(all_localization, localizable_nodes, organization_id) do
    localization_map = make_localization_map(all_localization)

    # get language labels here in one query for all languages if you want
    language_labels = Settings.locale_label_map(organization_id)
    language_keys = Map.keys(language_labels)

    # first collect all the strings that we need to translate
    translations =
      localizable_nodes
      |> Enum.reduce(
        %{},
        fn {action_uuid, action_text}, export ->
          localization_map
          |> Map.get(action_uuid, %{})
          |> collect_strings(language_labels, action_text, export)
        end
      )
      |> translate_strings()

    localizable_nodes
    |> Enum.reduce(
      [
        ["Type" | ["UUID" | Map.values(language_labels)]],
        ["Type" | ["UUID" | language_keys]]
      ],
      fn {action_uuid, action_text}, export ->
        row =
          localization_map
          |> Map.get(action_uuid, %{})
          |> make_row(language_labels, action_text, translations)

        [["action" | [action_uuid | row]] | export]
      end
    )
    |> Enum.reverse()
  end

  defp collect_strings(action_languages, language_labels, default_text, collect) do
    language_labels
    |> Map.keys()
    |> Enum.reduce(
      collect,
      fn language, acc ->
        if language == "en" do
          acc
        else
          translation = Map.get(action_languages, language, "")

          if translation == "" do
            Map.update(
              acc,
              {language_labels["en"], language_labels[language]},
              [default_text],
              fn curr -> [default_text | curr] end
            )
          else
            acc
          end
        end
      end
    )
  end

  defp translate_strings(strings) do
    strings
    |> Enum.reduce(
      %{},
      fn {{src, dst}, values}, acc ->
        {:ok, result} = Translate.translate(values, src, dst)

        Enum.zip(values, result)
        |> Map.new()
        |> then(&Map.put(acc, {src, dst}, &1))
      end
    )
  end

  defp make_row(action_languages, language_labels, default_text, translations) do
    language_labels
    |> Map.keys()
    |> Enum.reduce(
      [default_text],
      fn language, acc ->
        if language == "en" do
          acc
        else
          translation = Map.get(action_languages, language, "")

          if translation == "" do
            [
              Map.get(
                # first get all the translations for that specific
                # src, dst pair
                Map.get(
                  translations,
                  {language_labels["en"], language_labels[language]}
                ),
                default_text,
                ""
              )
              | acc
            ]
          else
            [translation | acc]
          end
        end
      end
    )
    |> Enum.reverse()
  end

  @spec get_non_null(map()) :: String.t() | nil
  defp get_non_null(%{"text" => value}), do: hd(value)
  defp get_non_null(%{"name" => value}), do: hd(value)
  defp get_non_null(%{"arguments" => value}), do: hd(value)
  defp get_non_null(_translation), do: nil

  # lets transform the localization to a map
  # whose key is the node uuid, and values are the languages it has
  @spec make_localization_map(map()) :: map()
  defp make_localization_map(all_localization) do
    all_localization
    # For all languages
    |> Enum.reduce(
      %{},
      fn {language_local, localization}, localization_map ->
        localization
        # For all nodes that have a translation
        |> Enum.reduce(
          localization_map,
          fn {uuid, translation}, acc ->
            update_localization_map({uuid, translation}, acc, language_local)
          end
        )
      end
    )
  end

  @spec update_localization_map(tuple(), map(), String.t()) :: map()
  defp update_localization_map({uuid, translation}, acc, language_local) do
    # add the language to the localization_map for that node
    # the translation is either under
    # "name" (categories), "arguments" (cases), "text" (send message)
    trans = get_non_null(translation)

    if trans,
      do:
        Map.update(
          acc,
          uuid,
          %{language_local => trans},
          fn existing -> Map.put(existing, language_local, trans) end
        ),
      else: acc
  end
end
