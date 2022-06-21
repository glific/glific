defmodule Glific.Clients.Tap do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.ContactField,
    Groups.ContactGroup,
    Groups.Group,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient,
    Templates.SessionTemplate
  }

  @props %{
    sheet_links: %{
      activity:
        "https://docs.google.com/spreadsheets/d/e/2PACX-1vR-GBWadR2F3QKZ43jaUwS9WYy0QQ5n_AMW4FN5AziwrEuNcfFr5__5zsO1nMNX04M1BmvChBaXTU9r/pub?gid=2079471637&single=true&output=csv",
      quiz:
        "https://docs.google.com/spreadsheets/d/e/2PACX-1vR-GBWadR2F3QKZ43jaUwS9WYy0QQ5n_AMW4FN5AziwrEuNcfFr5__5zsO1nMNX04M1BmvChBaXTU9r/pub?gid=720505613&single=true&output=csv"
    }
  }

  @doc """
  In the case of TAP we retrive the first group the contact is in and store
  and set the remote name to be a sub-directory under that group (if one exists)
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    group_name =
      Contact
      |> where([c], c.id == ^media["contact_id"])
      |> join(:inner, [c], cg in ContactGroup, on: c.id == cg.contact_id)
      |> join(:inner, [_c, cg], g in Group, on: cg.group_id == g.id)
      |> select([_c, _cg, g], g.label)
      |> order_by([_c, _cg, g], g.label)
      |> first()
      |> Repo.one()

    if is_nil(group_name),
      do: media["remote_name"],
      else: group_name <> "/" <> media["remote_name"]
  end

  @doc """
  get template form EEx without variables
  """
  @spec template(String.t(), String.t()) :: binary
  def template(shortcode, params_staring \\ "") do
    {:ok, template} = Repo.fetch_by(SessionTemplate, %{shortcode: shortcode})

    %{
      uuid: template.uuid,
      name: "Template",
      expression: nil,
      variables: parse_template_vars(template, params_staring)
    }
    |> Jason.encode!()
  end

  defp parse_template_vars(template, params_staring) do
    params = String.split(params_staring || "", "|", trim: true)

    if length(params) == template.number_parameters do
      params
    else
      params_with_missing =
        params ++ Enum.map(1..template.number_parameters, fn _i -> "{{ missing var  }}" end)

      Enum.take(params_with_missing, template.number_parameters)
    end
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("load_activities", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_activities()

    fields
  end

  def webhook("load_quizes", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_quizes()

    fields
  end

  def webhook("get_activity_info", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_activity_info(fields["date"], fields["type"], fields["language_label"])
  end

  def webhook("get_quiz_info", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_quiz_info(fields["activity_id"])
  end

  def webhook("get_quiz_question", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_quiz_question(fields["activity_id"], fields["question_id"], fields["language_label"])
  end

  def webhook("validate_question_answer", fields) do
    user_input = Glific.string_clean(fields["user_input"])
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

  def webhook("mark_activity_as_complete", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> mark_activity_as_complete(
      fields["activity_id"],
      fields["contact"]["id"]
    )
  end

  def webhook(_, fields), do: fields

  @spec load_activities(non_neg_integer()) :: :ok
  defp load_activities(org_id) do
    ApiClient.get_csv_content(url: @props.sheet_links.activity)
    |> Enum.each(fn {_, row} ->
      key = "schedule_" <> row["Schedule"]
      activity_type = Glific.string_clean(row["Activity type"])
      info = %{activity_type => row}
      Partners.maybe_insert_organization_data(key, info, org_id)
    end)
  end

  @spec load_quizes(non_neg_integer()) :: :ok
  defp load_quizes(org_id) do
    ApiClient.get_csv_content(url: @props.sheet_links.quiz)
    |> Enum.each(fn {_, row} ->
      row = clean_row_values(row)
      question_key = Glific.string_clean(row["Question Id"])
      key = "quiz_" <> row["Activity"] <> "_" <> question_key
      row = Map.put(row, "question_key", question_key)
      Partners.maybe_insert_organization_data(key, row, org_id)
    end)
  end

  @spec get_activity_info(non_neg_integer(), String.t(), String.t(), String.t()) :: map()
  defp get_activity_info(org_id, date, type, language_label) do
    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: "schedule_" <> date
    })
    |> case do
      {:ok, data} ->
        data.json[type]
        |> clean_map_keys()
        |> format_hsm_templates(language_label)
        |> Map.merge(%{
          is_valid: true,
          message: "Activity found"
        })

      _ ->
        %{
          is_valid: false,
          message: "Worksheet code not found"
        }
    end
  end

  defp get_quiz_question(org_id, activity_id, question_id, language_label) do
    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: "quiz_" <> activity_id <> "_" <> question_id
    })
    |> case do
      {:ok, data} ->
        data.json
        |> clean_map_keys()
        |> format_quiz_question(language_label)

      _ ->
        %{
          is_valid: false,
          message: "Question not found"
        }
    end
  end

  defp format_quiz_question(question_data, langauge_label) do
    questions_answers =
      case langauge_label do
        "English" ->
          %{
            valid_answers: question_data["validresponsesenglish"],
            correct_response: question_data["answerenglish"],
            question: question_data["questionmessageenglish"]
          }

        "Hindi" ->
          %{
            valid_answers: question_data["validresponseshindi"],
            correct_response: question_data["answerhindi"],
            question: question_data["questionmessagehindi"]
          }

        "Kannada" ->
          %{
            valid_answers: question_data["validresponseshindi"],
            correct_response: question_data["answerhindi"],
            question: question_data["questionmessagehindi"]
          }

        _ ->
          %{}
      end

    buttons =
      questions_answers.valid_answers
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", answer} end)
      |> Enum.into(%{})

    Map.merge(
      question_data,
      %{
        buttons: buttons,
        button_count: length(Map.keys(buttons))
      }
    )
    |> Map.merge(questions_answers)
  end

  @spec get_quiz_info(non_neg_integer(), String.t()) :: map()
  defp get_quiz_info(org_id, activity_id) do
    quizes =
      Partners.list_organization_data(%{
        organization_id: org_id,
        filter: %{
          key: "quiz_" <> activity_id
        }
      })

    Enum.reduce(quizes, %{}, fn row, acc ->
      data = row.json
      Map.put(acc, data["question_key"], clean_map_keys(data))
    end)
  end

  defp format_hsm_templates(activity_info, langauge_lable) do
    templates =
      case langauge_lable do
        "English" ->
          %{
            intro: %{
              shortcode: activity_info["introtemplateuuidenglish"],
              params: activity_info["introtemplatevariablesenglish"]
            },
            intro_no_response: %{
              shortcode: activity_info["intronoresponsenudgetemplateuuidenglish"],
              params: activity_info["intronoresponsenudgetemplatevariablesenglish"]
            },
            submission_first_no_response: %{
              shortcode: activity_info["activitysubmissionfirstnoresponsetemplatemessageenglish"],
              params: activity_info["activitysubmissionfirstnoresponsetemplatevariablesenglish"]
            },
            submission_second_no_response: %{
              shortcode: activity_info["activitysubmissionsecondnoresponsetemplateuuidenglish"],
              params: activity_info["activitysubmissionsecondnoresponsetemplatevariablesenglish"]
            }
          }

        "Hindi" ->
          %{
            intro: %{
              shortcode: activity_info["introtemplateuuidhindi"],
              params: activity_info["introtemplatevariableshindi"]
            },
            intro_no_response: %{
              shortcode: activity_info["intronoresponsenudgetemplateuuidhindi"],
              params: activity_info["intronoresponsenudgetemplatevariableshindi"]
            },
            submission_first_no_response: %{
              shortcode: activity_info["activitysubmissionfirstnoresponsetemplatemessagehindi"],
              params: activity_info["activitysubmissionfirstnoresponsetemplatevariableshindi"]
            },
            submission_second_no_response: %{
              shortcode: activity_info["activitysubmissionsecondnoresponsetemplateuuidhindi"],
              params: activity_info["activitysubmissionsecondnoresponsetemplatevariableshindi"]
            }
          }

        "Marathi" ->
          %{
            intro: %{
              shortcode: activity_info["introtemplateuuidenglish"],
              params: activity_info["introtemplatevariablesenglish"]
            },
            intro_no_response: %{
              shortcode: activity_info["intronoresponsenudgetemplateuuidenglish"],
              params: activity_info["intronoresponsenudgetemplatevariablesenglish"]
            },
            submission_first_no_response: %{
              shortcode: activity_info["activitysubmissionfirstnoresponsetemplatemessageenglish"],
              params: activity_info["activitysubmissionfirstnoresponsetemplatevariablesenglish"]
            },
            submission_second_no_response: %{
              shortcode: activity_info["activitysubmissionsecondnoresponsetemplateuuidenglish"],
              params: activity_info["activitysubmissionsecondnoresponsetemplatevariablesenglish"]
            }
          }

        _ ->
          %{}
      end

    Map.merge(activity_info, templates)
  end

  @spec clean_map_keys(map()) :: map()
  defp clean_map_keys(data) do
    data
    |> Enum.map(fn {k, v} -> {Glific.string_clean(k), v} end)
    |> Enum.into(%{})
  end

  @spec mark_activity_as_complete(non_neg_integer(), String.t(), non_neg_integer()) :: map()
  defp mark_activity_as_complete(_org_id, activity_id, contact_id) do
    contact = Repo.get!(Contact, contact_id)
    completed_activities = get_in(contact.fields, ["completed_activities", "value"])

    completed_activities =
      if is_nil(completed_activities), do: activity_id, else: ", #{activity_id}"

    ContactField.do_add_contact_field(
      contact,
      "completed_activities",
      "completed_activities",
      completed_activities
    )

    completed_activities_count =
      completed_activities
      |> String.split(",", trim: true)
      |> Enum.uniq_by(&String.trim(&1))
      |> length()

    ContactField.do_add_contact_field(
      contact,
      "completed_activities_count",
      "completed_activities_count",
      completed_activities_count
    )

    %{
      completed_activities: completed_activities,
      completed_activities_count: completed_activities_count
    }
  end

  defp clean_row_values(row) do
    row
    |> Enum.map(fn
      {k, v} when is_list(v) -> {k, hd(v)}
      {k, v} -> {k, v}
    end)
    |> Enum.into(%{})
  end
end
