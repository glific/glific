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
    Flows.Flow,
    Partners.Organization,
    Repo,
    Settings
  }

  @doc """
  import the csv structure (list of lists) and create the localization
  json that fits into the floweditor json format

  At some point, we might extend this to import it from a .po file
  Lets keep the csv part very distinct from the json
  """
  @spec import_localization(list(), map()) :: any()
  def import_localization(csv, flow) do
    # get language labels here in one query for all languages if you want
    language_labels = Settings.locale_label_map(flow.organization_id)
    language_keys = Map.keys(language_labels)

    [_header_1 | [_header_2 | rows]] = csv

    {:ok, _revision} =
      rows
      |> collect_by_language(language_keys, flow)
      |> merge_with_latest_localization(flow)
      |> Flows.update_flow_localization(flow)
  end

  @spec collect_by_language(list(), list(), map()) :: map()
  defp collect_by_language(rows, language_keys, flow) do
    organization = Repo.get(Organization, flow.organization_id) |> Repo.preload(:default_language)

    rows
    |> Enum.reduce(%{}, fn row, acc ->
      [_type | [uuid | translations]] = row

      translations
      |> Enum.zip(language_keys)
      |> Enum.reduce(acc, fn {translation, lang_key}, acc ->
        # skip the default language during processing
        if lang_key == organization.default_language.locale do
          acc
        else
          update_language_map(acc, %{
            flow: flow,
            lang_key: lang_key,
            uuid: uuid,
            translation: translation
          })
        end
      end)
    end)
  end

  @spec update_language_map(map(), map()) :: map()
  defp update_language_map(acc, %{
         flow: flow,
         lang_key: lang_key,
         uuid: uuid,
         translation: translation
       }) do
    localized = Map.get(flow.definition["localization"], lang_key, %{})
    translation_data = Map.get(localized, uuid, %{})

    text = [translation]
    attachments = Map.get(translation_data, "attachments", [])

    data =
      if attachments != [],
        do: %{"text" => text, "attachments" => attachments},
        else: %{"text" => text}

    Map.update(acc, lang_key, %{uuid => data}, fn value ->
      Map.put(value, uuid, data)
    end)
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
    # don't overwrite what currently exists
    |> Map.merge(
      translations,
      fn _k, c_v, t_v -> if map_size(c_v) == 0, do: t_v, else: c_v end
    )
  end
end
