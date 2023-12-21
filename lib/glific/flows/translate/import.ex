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

    collect_by_language(rows, language_keys)
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
        Map.put(acc, k, Map.new(v))
      end
    )
  end
end
