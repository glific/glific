defmodule Glific.Flows.Translate.Import do
  @moduledoc """
  Given a csv list, and a flow
  import the resulting csv and replace it in the flow definition
  json

  We need to add validation checks to the csv to ensure that the csv
  we import matches the flow we are importing into. For that we will embed
  a csv line with meta information on flow uuid which does not change
  """

  alias Glific.{
    Flows,
    Settings
  }

  @doc """
  import the csv structure (list of lists) and create the localization
  json that fits into the floweditor json format

  At some point, we might extend this to import it from a .po file
  Lets keep the csv part very distict from the json
  """
  @spec import_localization(list(), map()) :: map()
  def import_localization(csv, flow) do
    # get language labels here in one query for all languages if you want
    language_labels = Settings.locale_label_map(flow.organization_id)
    language_keys = Map.keys(language_labels)

    [_header | rows] = csv

    rows
    |> collect_by_language(language_keys)
    |> merge_with_latest_localization(flow)
    |> Flows.update_flow_localization(flow)
  end

  defp collect_by_language(rows, language_keys) do
    rows
    |> Enum.reduce(
      %{},
      fn row, acc ->
        [_type | [uuid | translations]] = row

        translations
        |> Enum.zip(language_keys)
        |> Enum.reduce(
          acc,
          fn {translation, lang_key}, acc ->
            Map.update(acc, lang_key, [{uuid, translation}], fn value ->
              [{uuid, %{text: [translation]}} | value]
            end)
          end
        )
      end
    )
    |> Enum.reduce(
      %{},
      fn {k, v}, acc ->
        # convert tuples to a map for json
        Map.put(acc, k, Map.new(v))
      end
    )
  end

  # the flow might have changed between when we exported the localization
  # and imported it, so we merge the old with the new to pick up any remainder stuff
  # Note that if a specific translation or text changed etc, we do not account for those
  @spec merge_with_latest_localization(map(), Flow.t()) :: map()
  defp merge_with_latest_localization(translations, flow) do
    flow.definition["localization"]
    |> Enum.reduce(
      %{},
      fn {curr_k, curr_v}, acc ->
        # merge all the values from current that are not present in translations
        Map.put(
          acc,
          curr_k,
          Map.merge(
            Map.get(translations, curr_k, %{}),
            curr_v,
            # translations win, unless the translation does not exist
            fn _k, t_v, c_v -> if map_size(t_v) == 0, do: c_v, else: t_v end
          )
        )
      end
    )
    # if there are languages missing, merge them also
    # dont overwrite what currently exists
    |> Map.merge(
      translations,
      fn _k, c_v, t_v -> if map_size(c_v) == 0, do: t_v, else: c_v end
    )
  end
end
