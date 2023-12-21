defmodule Glific.Flows.Translate.Export do
  @moduledoc """
  Lets parse the localization map into a structure that is convenient
  to export out of the json flow and to import back into the json flow
  """

  alias Glific.{
    Settings
  }

  @doc """
  Export the localization json as a csv structure (list of lists).
  At some point, we might extend this to export it as a .po file
  Lets keep the csv generation very distict from the extraction
  """
  @spec export_localization(map()) :: list()
  def export_localization(flow) do
    missing_localization(flow, flow.definition["localization"])
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
    |> add_missing_translations()
  end

  @spec add_missing_localization(map(), list(), non_neg_integer()) :: Keyword.t()
  defp add_missing_localization(all_localization, localizable_nodes, organization_id) do
    localization_map = make_localization_map(all_localization)

    # get language labels here in one query for all languages if you want
    language_labels = Settings.locale_label_map(organization_id)
    language_keys = Map.keys(language_labels)

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
          |> make_row(language_keys, action_text)

        [["action" | [action_uuid | row]] | export]
      end
    )
    |> Enum.reverse()
  end

  defp make_row(action_languages, language_keys, default_text) do
    language_keys
    |> Enum.reduce(
      [default_text],
      fn language, acc ->
        if language == "en", do: acc, else: [Map.get(action_languages, language, "") | acc]
      end
    )
    |> Enum.reverse()
  end

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
            # add the language to the localization_map for that node
            Map.update(
              acc,
              uuid,
              %{language_local => hd(Map.get(translation, "text"))},
              fn existing -> Map.put(existing, language_local, translation) end
            )
          end
        )
      end
    )
  end

  @spec add_missing_translations(list()) :: list()
  defp add_missing_translations(translations) do
    tuples =
      translations
      # lets skip the language keys row
      |> tl()
      # zip the rest
      |> Enum.zip()
      # skip type tuple
      |> tl()
      # skip uuid row
      |> tl()

    # lets assume the first tuple is the src
    # the rest are destination
    [src | dst_s] = tuples

    # lets fill in all the destinations and return the same set of tuples
    dst_s
    |> Enum.reduce(
      [src],
      fn dst, acc ->
        [translate(src, dst) | acc]
      end
    )
    |> Enum.reverse()
  end

  @spec translate(tuple(), tuple()) :: tuple()
  defp translate(src, dst) do
    src
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(dst))
    |> translate_all()
    |> List.to_tuple()
  end

  @spec translate_all(list()) :: list()
  defp translate_all(strings) do
    [{src, dst} | rows] = strings

    rows
    |> Enum.reduce(
      [dst],
      fn row, acc ->
        [translate_one(row, src, dst) | acc]
      end
    )
    |> Enum.reverse()
  end

  @spec translate_one(tuple(), String.t(), String.t()) :: String.t()
  defp translate_one({orig, ""}, src, dst) do
    "#{dst} #{orig} #{src}"
  end

  defp translate_one({_orig, translation}, _src, _dst), do: "NOP: #{translation}"
end
