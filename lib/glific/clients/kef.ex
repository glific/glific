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
    Sheets.ApiClient
  }

  alias Glific.Sheets.ApiClient

  @props %{
    worksheets: %{
      sheet_links: %{
        prekg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=89165000&single=true&output=csv",
        lkg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=531803735&single=true&output=csv",
        ukg:
          "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=1715409890&single=true&output=csv",
      }
    },
    school_ids_sheet_link: "https://docs.google.com/spreadsheets/d/e/2PACX-1vQPzJ4BruF8RFMB0DwBgM8Rer7MC0fiL_IVC0rrLtZT7rsa3UnGE3ZTVBRtNdZI9zGXGlQevCajwNcn/pub?gid=1503063199&single=true&output=csv"
  }

  @doc """
  Generate custom GCS bucket name based on group that the contact is in (if any)
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    {:ok, contact} =
      Repo.fetch_by(Contacts.Contact, %{
        id: media["contact_id"],
        organization_id: media["organization_id"]
      })

    school_id = get_in(contact.fields, ["school_id", "value"])
    phone = contact.phone

    if is_nil(school_id),
    do: media["remote_name"],
    else: "schools/#{school_id}/#{phone}" <> "/" <> media["remote_name"]
  end

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
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    completed_worksheet_codes =
      get_in(fields, ["contact", "fields", "completed_worksheet_code", "value"]) || ""

    completed_worksheet_codes =
      if completed_worksheet_codes == "",
        do: worksheet_code,
        else: "#{completed_worksheet_codes}, #{worksheet_code}"

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field(
      "completed_worksheet_code",
      "completed_worksheet_code",
      completed_worksheet_codes
    )

    %{
      error: false,
      message: "Worksheet #{worksheet_code} marked as completed"
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
        list: Enum.join(uniq_completed_worksheets, ",")
      },
      helping_hand: %{
        completed: length(uniq_completed_helping_hands),
        list: Enum.join(uniq_completed_helping_hands, ","),
        total: 3
      }
    }
  end

  @spec webhook(String.t(), map()) :: map()
  def webhook("get_school_id_info", fields) do
    school_id = Glific.string_clean(fields["school_id"] || "")
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_school_id_info(school_id)
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

  @spec load_school_ids(non_neg_integer()) :: map()
  defp load_school_ids(org_id) do
    ApiClient.get_csv_content(url: @props.school_ids_sheet_link)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      school_id = row["School ID"]
      if school_id in [nil, ""], do: acc, else: Map.put(acc, Glific.string_clean(school_id), clean_map_keys(row))
    end)
    |> then(fn school_ids_data ->
      Partners.maybe_insert_organization_data("school_ids_data", school_ids_data, org_id)
    end)
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
        %{
          is_valid: Map.has_key?(data.json, school_id),
          info: data.json[school_id]
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
end
