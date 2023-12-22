defmodule Glific.Clients.KEF do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  require Logger

  alias Glific.{
    Contacts,
    Flows.ContactField,
    Partners,
    Partners.OrganizationData,
    Repo,
    Settings.Language,
    Sheets.ApiClient
  }

  @worksheet_flow_ids [8880, 8176]

  @props %{
    worksheets: %{
      sheet_links: %{
        prekg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=89165000&single=true&output=csv",
        lkg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=531803735&single=true&output=csv",
        ukg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=1715409890&single=true&output=csv"
      }
    },
    school_ids_sheet_link:
      "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=1503063199&single=true&output=csv"
  }

  @doc """
  Generate custom GCS bucket name based on group that the contact is in (if any)
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    flow_id = media["flow_id"]

    {:ok, contact} =
      Repo.fetch_by(Contacts.Contact, %{
        id: media["contact_id"],
        organization_id: media["organization_id"]
      })

    contact_type = get_in(contact.fields, ["contact_type", "value"])

    phone = contact.phone

    folder_structure = get_folder_structure(media, contact_type, contact.fields)

    media_subfolder =
      case media["type"] do
        "image" -> "Images"
        "video" -> "Videos"
        "audio" -> "Audio note"
        _ -> "Others"
      end

    if flow_id == 13_850 do
      "stories_activities_campaign/#{media_subfolder}/#{phone}/" <> media["remote_name"]
    else
      "#{folder_structure}/#{media_subfolder}/#{phone}/" <> media["remote_name"]
    end
  end

  @spec get_folder_structure(map(), String.t(), map()) :: String.t()
  defp get_folder_structure(media, contact_type, fields) do
    current_worksheet_code = get_in(fields, ["current_worksheet_code", "value"])

    with {:ok, school_id} <- get_school_id(contact_type, fields),
         {:ok, school_name} <- get_school_name(contact_type, fields),
         {:ok, flow_subfolder} <- get_flow_subfolder(media["flow_id"], current_worksheet_code) do
      "#{school_name}/#{school_id}/#{flow_subfolder}"
    else
      _ -> "Ungrouped users"
    end
  end

  @spec get_school_id(nil | String.t(), map()) :: {:error, String.t()} | {:ok, String.t()}
  defp get_school_id(nil, _fields), do: {:error, "Invalid contact_type"}

  defp get_school_id("Parent", fields) do
    school_id = get_in(fields, ["usersschoolid", "value"])
    {:ok, school_id}
  end

  defp get_school_id("Teacher", fields) do
    school_id = get_in(fields, ["child_school_id", "value"])
    {:ok, school_id}
  end

  @spec get_school_name(nil | String.t(), map()) :: {:error, String.t()} | {:ok, String.t()}
  defp get_school_name(nil, _fields), do: {:error, "Invalid contact_type"}

  defp get_school_name("Parent", fields) do
    school_name = get_in(fields, ["child_school_name", "value"])
    {:ok, school_name}
  end

  defp get_school_name("Teacher", fields) do
    school_name = get_in(fields, ["school_name", "value"])
    {:ok, school_name}
  end

  @spec get_flow_subfolder(non_neg_integer(), String.t()) ::
          {:error, String.t()} | {:ok, String.t()}
  defp get_flow_subfolder(flow_id, current_worksheet_code) when flow_id in @worksheet_flow_ids do
    {:ok, "Worksheets/#{current_worksheet_code}"}
  end

  defp get_flow_subfolder(8842, _current_worksheet_code) do
    {:ok, "Videos/Video 1"}
  end

  defp get_flow_subfolder(9870, _current_worksheet_code) do
    {:ok, "Videos/Video 2"}
  end

  defp get_flow_subfolder(_flow_id, nil), do: {:ok, "Others"}

  defp get_flow_subfolder(_flow_id, _current_worksheet_code), do: {:ok, "Others"}

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("load_worksheets", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_worksheets()

    fields
  end

  def webhook("load_school_ids", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_school_ids()

    fields
  end

  def webhook("validate_worksheet_code", fields) do
    status =
      Glific.parse_maybe_integer!(fields["organization_id"])
      |> validate_worksheet_code(fields["worksheet_code"])

    %{
      is_vaid: status
    }
  end

  def webhook("get_worksheet_info", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_worksheet_info(fields["worksheet_code"])
    |> interactive_message_reflection_question(fields["language_label"])
  end

  def webhook("get_interactive_message_reflection_question", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_worksheet_info(fields["worksheet_code"])
    |> interactive_message_reflection_question(fields["language_label"])
  end

  def webhook("validate_reflection_response", fields) do
    user_input = Glific.string_clean(fields["user_answer"])
    correct_answer = Glific.string_clean(fields["correct_answer"])

    in_valid_answer_range =
      fields["valid_answers"]
      |> String.split("|", trim: true)
      |> Enum.map(&Glific.string_clean(&1))
      |> Enum.member?(user_input)

    cond do
      user_input == correct_answer ->
        %{status: "correct_response"}

      correct_answer == "allanswers" && in_valid_answer_range ->
        %{status: "correct_response"}

      in_valid_answer_range ->
        %{status: "incorrect_response"}

      true ->
        %{status: "out_of_range"}
    end
  end

  def webhook("mark_worksheet_completed", fields) do
    worksheet_code = String.trim(fields["worksheet_code"] || "")
    worksheet_grade = String.trim(fields["worksheet_grade"] || "")
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    completed_worksheet_codes =
      get_in(fields, ["contact", "fields", "completed_worksheet_code", "value"]) || ""

    completed_worksheet_codes =
      if completed_worksheet_codes == "",
        do: worksheet_code,
        else: "#{completed_worksheet_codes}, #{worksheet_code}_#{worksheet_grade}"

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field(
      "completed_worksheet_code",
      "completed_worksheet_code",
      completed_worksheet_codes
    )

    %{
      error: false,
      message: "Worksheet #{worksheet_code}_#{worksheet_grade} marked as completed"
    }
  end

  def webhook("mark_helping_hand_complete", fields) do
    helping_hand_topic = String.trim(fields["helping_hand_topic"] || "")
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    completed_helping_hand_topics =
      get_in(fields, ["contact", "fields", "completed_helping_hand_topic", "value"]) || ""

    completed_helping_hand_topics =
      if completed_helping_hand_topics == "",
        do: helping_hand_topic,
        else: "#{completed_helping_hand_topics}, #{helping_hand_topic}"

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field(
      "completed_helping_hand_topic",
      "completed_helping_hand_topic",
      completed_helping_hand_topics
    )

    %{
      error: false,
      message: "Helping hand #{helping_hand_topic} marked as completed"
    }
  end

  def webhook("get_reports_info", fields) do
    language = get_language(fields["contact"]["id"])

    uniq_completed_worksheets =
      get_in(fields, ["contact", "fields"])
      |> get_completed_worksheets()

    uniq_completed_helping_hands =
      get_in(fields, ["contact", "fields"])
      |> get_completed_helping_hands()

    %{
      worksheet: %{
        completed: length(uniq_completed_worksheets),
        remaining: 36 - length(uniq_completed_worksheets),
        list: Enum.join(uniq_completed_worksheets, ","),
        list_message: get_worksheet_msg(uniq_completed_worksheets, language)
      },
      helping_hand: %{
        completed: length(uniq_completed_helping_hands),
        list: Enum.join(uniq_completed_helping_hands, ","),
        total: 1
      }
    }
  end

  def webhook("get_school_id_info", fields) do
    school_id = fields["school_id"] || ""

    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_school_id_info(school_id)
  end

  def webhook("check_is_completed_worksheet", fields) do
    worksheet_code = String.trim(fields["worksheet_code"] || "")

    completed_worksheet_codes =
      get_in(fields, ["contact", "fields", "sheet_completed_worksheet_code", "value"]) || ""

    is_completed = worksheet_code in String.split(completed_worksheet_codes, ", ")

    %{
      error: false,
      is_completed: is_completed
    }
  end

  def webhook("get_question_buttons", fields) do
    buttons =
      fields["question"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields) do
    %{
      response: String.equivalent?(fields["correct_response"], fields["user_response"])
    }
  end

  def webhook("mark_sheet_worksheet_completed", fields) do
    worksheet_code = String.trim(fields["worksheet_code"] || "")
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    sheet_completed_worksheet_codes =
      get_in(fields, ["contact", "fields", "sheet_completed_worksheet_code", "value"]) || ""

    sheet_completed_worksheet_codes =
      if sheet_completed_worksheet_codes == "" do
        worksheet_code
      else
        "#{sheet_completed_worksheet_codes}, #{worksheet_code}"
      end

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field(
      "sheet_completed_worksheet_code",
      "sheet_completed_worksheet_code",
      sheet_completed_worksheet_codes
    )

    %{
      error: false,
      message: "Worksheet #{worksheet_code} marked as completed"
    }
  end

  def webhook("check_is_topic_already_watched", fields) do
    current_topic = String.trim(fields["current_topic"] || "")

    already_watched_topics =
      get_in(fields, ["contact", "fields", "watched_topics", "value"]) || ""

    is_watched = current_topic in String.split(already_watched_topics, ", ")

    %{
      error: false,
      is_watched: is_watched
    }
  end

  def webhook("mark_video_topic_watched", fields) do
    current_topic = String.trim(fields["current_topic"] || "")
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    already_watched_topics =
      get_in(fields, ["contact", "fields", "watched_topics", "value"]) || ""

    already_watched_topics =
      if already_watched_topics == "" do
        current_topic
      else
        "#{already_watched_topics}, #{current_topic}"
      end

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field(
      "watched_topics",
      "watched_topics",
      already_watched_topics
    )

    %{
      error: false,
      message: "Topic #{current_topic} marked as watched"
    }
  end

  def webhook("total_topics_watched", fields) do
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    watched_topics = String.trim(fields["contact"]["fields"]["watched_topics"]["value"] || "")
    watched_topics_list = String.split(watched_topics, ",")
    number_of_topics_watched = length(watched_topics_list)

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field(
      "number_of_topics_watched",
      "number_of_topics_watched",
      number_of_topics_watched
    )

    %{
      error: false,
      message: "Total topics watched #{number_of_topics_watched}"
    }
  end

  def webhook(_, _) do
    raise "Unknown webhook"
  end

  @spec load_worksheets(non_neg_integer()) :: map()
  defp load_worksheets(org_id) do
    @props.worksheets.sheet_links
    |> Enum.each(fn {k, v} -> do_load_code_worksheet(k, v, org_id) end)

    %{status: "successfull"}
  end

  @spec do_load_code_worksheet(String.t(), String.t(), non_neg_integer()) :: :ok
  defp do_load_code_worksheet(class, sheet_link, org_id) do
    ApiClient.get_csv_content(url: sheet_link)
    |> Enum.each(fn {_, row} ->
      row = Map.put(row, "class", class)
      row = Map.put(row, "code", row["Worksheet Code"])
      key = clean_worksheet_code(row["Worksheet Code"] || "")
      Partners.maybe_insert_organization_data(key, row, org_id)
    end)
  end

  @spec load_school_ids(non_neg_integer()) :: :ok
  defp load_school_ids(org_id) do
    ApiClient.get_csv_content(url: @props.school_ids_sheet_link)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      school_id = row["School ID"]

      if school_id in [nil, ""],
        do: acc,
        else: Map.put(acc, Glific.string_clean(school_id), clean_map_keys(row))
    end)
    |> then(fn school_ids_data ->
      Partners.maybe_insert_organization_data("school_ids_data", school_ids_data, org_id)
    end)

    :ok
  end

  @spec validate_worksheet_code(non_neg_integer(), String.t()) :: boolean()
  defp validate_worksheet_code(org_id, worksheet_code) do
    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: clean_worksheet_code(worksheet_code)
    })
    |> case do
      {:ok, _data} -> true
      _ -> false
    end
  end

  @spec get_worksheet_info(non_neg_integer(), String.t()) :: map()
  defp get_worksheet_info(org_id, worksheet_code) do
    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: clean_worksheet_code(worksheet_code)
    })
    |> case do
      {:ok, data} ->
        data.json
        |> clean_map_keys()
        |> Map.put("worksheet_code", worksheet_code)
        |> Map.put("is_valid", true)
        |> Map.put("worksheet_code_label", worksheet_code)

      _ ->
        %{
          is_valid: false,
          message: "Worksheet code not found"
        }
    end
  end

  @spec get_school_id_info(non_neg_integer(), String.t()) :: map()
  defp get_school_id_info(org_id, school_id) do
    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: "school_ids_data"
    })
    |> case do
      {:ok, data} ->
        {key, value} =
          data.json
          |> Enum.find(fn {_k, v} ->
            v["userinputcorrectcode"]
            |> Glific.string_clean()
            |> String.equivalent?(school_id)
          end) || {nil, nil}

        %{
          is_valid: key != nil,
          info: value
        }

      _ ->
        %{
          is_valid: false,
          message: "Worksheet code not found"
        }
    end
  end

  @spec interactive_message_reflection_question(map(), String.t()) :: map()
  defp interactive_message_reflection_question(worksheet_code_info, langauge_label) do
    get_reflection_question_answer_count(worksheet_code_info, langauge_label)
    |> Map.merge(%{
      worksheet_code: worksheet_code_info["code"],
      langauge_label: langauge_label
    })
    |> Map.merge(worksheet_code_info)
  end

  @spec get_reflection_question_answer_count(map(), String.t()) :: map()
  defp get_reflection_question_answer_count(worksheet_code_info, langauge_label) do
    refelction_answers =
      case langauge_label do
        "English" ->
          %{
            valid_answers: worksheet_code_info["reflectionquestionvalidresponses"],
            correct_response: worksheet_code_info["reflectionquestionanswer"]
          }

        "Hindi" ->
          %{
            valid_answers: worksheet_code_info["reflectionquestionvalidresponseshindi"],
            correct_response: worksheet_code_info["reflectionquestionanswerhindi"]
          }

        "Kannada" ->
          %{
            valid_answers: worksheet_code_info["reflectionquestionvalidresponseskan"],
            correct_response: worksheet_code_info["reflectionquestionanswerkan"]
          }

        _ ->
          %{}
      end

    buttons =
      refelction_answers.valid_answers
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", answer} end)
      |> Enum.into(%{})

    Map.merge(
      refelction_answers,
      %{
        buttons: buttons,
        button_count: length(Map.keys(buttons))
      }
    )
  end

  @spec clean_map_keys(map()) :: map()
  defp clean_map_keys(data) do
    data
    |> Enum.map(fn {k, v} -> {Glific.string_clean(k), v} end)
    |> Enum.into(%{})
  end

  @spec get_worksheet_msg(list(), Language.t()) :: String.t()
  defp get_worksheet_msg(completed_worksheets, language) do
    worksheet_count =
      completed_worksheets
      |> Enum.reduce(%{level_1: 0, level_2: 0, level_3: 0}, fn worksheet, acc ->
        cond do
          String.contains?(worksheet, "_prekg") ->
            Map.put(acc, :level_1, acc.level_1 + 1)

          String.contains?(worksheet, "_lkg") ->
            Map.put(acc, :level_2, acc.level_2 + 1)

          String.contains?(worksheet, "_ukg") ->
            Map.put(acc, :level_3, acc.level_3 + 1)

          true ->
            acc
        end
      end)

    do_get_worksheet_msg(worksheet_count, language.locale)
  end

  defp do_get_worksheet_msg(worksheet_count, "en") do
    """
    #{worksheet_count.level_1} worksheets for Level 1
    #{worksheet_count.level_2} worksheets for Level 2
    #{worksheet_count.level_3} worksheets for Level 3
    """
  end

  defp do_get_worksheet_msg(worksheet_count, "hi") do
    """
    स्तर 1 के #{worksheet_count.level_1} कार्यपत्रक
    स्तर 2 के #{worksheet_count.level_2} कार्यपत्रक
    स्तर 3 के #{worksheet_count.level_3} कार्यपत्रक
    """
  end

  defp do_get_worksheet_msg(worksheet_count, "kn") do
    """
    ಲೆವೆಲ್ 1 #{worksheet_count.level_1} ವರ್ಕ್‌ಶೀಟ್‌ಗಳು
    ಲೆವೆಲ್ 2 #{worksheet_count.level_2} ವರ್ಕ್‌ಶೀಟ್‌ಗಳು
    ಲೆವೆಲ್ 3 #{worksheet_count.level_3} ವರ್ಕ್‌ಶೀಟ್‌ಗಳು
    """
  end

  @spec get_completed_worksheets(map()) :: list()
  defp get_completed_worksheets(contact_fields) do
    completed_worksheet_codes =
      get_in(contact_fields, ["completed_worksheet_code", "value"]) || ""

    completed_worksheet_codes
    |> String.split(",", trim: true)
    |> Enum.uniq_by(&String.trim(&1))
  end

  @spec get_completed_helping_hands(map()) :: list()
  defp get_completed_helping_hands(contact_fields) do
    completed_helping_hands =
      get_in(contact_fields, ["completed_helping_hand_topic", "value"]) || ""

    completed_helping_hands
    |> String.split(",", trim: true)
    |> Enum.uniq_by(&String.trim(&1))
  end

  @spec clean_worksheet_code(String.t()) :: String.t()
  defp clean_worksheet_code(str) do
    code = Glific.string_clean(str)
    "worksheet_code_#{code}"
  end

  defp get_language(contact_id) do
    contact_id = Glific.parse_maybe_integer!(contact_id)

    contact =
      contact_id
      |> Contacts.get_contact!()
      |> Repo.preload([:language])

    contact.language
  end
end
