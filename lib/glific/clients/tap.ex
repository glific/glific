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
    [template | _tail] =
      SessionTemplate
      |> where([st], st.shortcode == ^shortcode)
      |> Repo.all()

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
    |> load_quizzes()

    fields
  end

  def webhook("get_activity_info", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    course = get_in(fields, ["contact", "fields", "course", "value"]) || fields["type"]
    date = get_in(fields, ["contact", "fields", "test_date", "value"]) || to_string(Timex.today())

    get_activity_info(org_id, date, course, fields["language_label"])
    |> maybe_add_profile_activity(fields["contact"]["id"], org_id)
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

  def webhook("update_all_profile_fields", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    update_all_profile_fields(org_id, contact_id, fields["key"], fields["value"])
    fields
  end

  def webhook(_, fields), do: fields

  @spec load_activities(non_neg_integer()) :: :ok
  defp load_activities(org_id) do
    ApiClient.get_csv_content(url: @props.sheet_links.activity)
    |> Enum.each(fn {_, row} ->
      row = clean_row_values(row)
      activity_type = Glific.string_clean(row["Activity type"])
      key = "schedule_" <> row["Schedule"] <> "_" <> activity_type

      info = %{activity_type => row}
      Partners.maybe_insert_organization_data(key, info, org_id)
    end)
  end

  @spec load_quizzes(non_neg_integer()) :: :ok
  defp load_quizzes(org_id) do
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
    type = Glific.string_clean(type)

    key = "schedule_" <> date <> "_" <> type

    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: key
    })
    |> case do
      {:ok, data} ->
        data.json[type]
        |> clean_map_keys()
        |> format_hsm_templates(language_label)
        |> Map.merge(%{
          "is_valid" => true,
          "message" => "Activity found"
        })

      _ ->
        %{
          "is_valid" => false,
          "message" => "Worksheet code not found"
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

  defp format_quiz_question(question_data, language_label) do
    questions_answers =
      case language_label do
        "English" ->
          %{
            valid_answers: question_data["validresponsesenglish"],
            correct_response: question_data["answerenglish"],
            question: question_data["questionmessageenglish"],
            attachment_url: question_data["attachmentenglish"]
          }

        "Hindi" ->
          %{
            valid_answers: question_data["validresponseshindi"],
            correct_response: question_data["answerhindi"],
            question: question_data["questionmessagehindi"],
            attachment_url: question_data["attachmenthindi"]
          }

        "Kannada" ->
          %{
            valid_answers: question_data["validresponseshindi"],
            correct_response: question_data["answerhindi"],
            question: question_data["questionmessagehindi"],
            attachment_url: question_data["attachmentenglish"]
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

    Map.merge(question_data, %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    })
    |> Map.merge(questions_answers)
  end

  @spec get_quiz_info(non_neg_integer(), String.t()) :: map()
  defp get_quiz_info(org_id, activity_id) do
    quizzes =
      Partners.list_organization_data(%{
        organization_id: org_id,
        filter: %{
          key: "quiz_" <> activity_id
        }
      })

    Enum.reduce(quizzes, %{}, fn row, acc ->
      data = row.json
      Map.put(acc, data["question_key"], clean_map_keys(data))
    end)
  end

  defp format_hsm_templates(activity_info, language_label) do
    templates =
      case language_label do
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
      if is_nil(completed_activities),
        do: "#{activity_id}",
        else: "#{completed_activities}, #{activity_id}"

    contact =
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
      {k, v} when is_list(v) -> {k, String.replace(hd(v), ~r/\n\r\n/, "\n")}
      {k, v} -> {k, String.replace(v, ~r/\n\r\n/, "\n")}
    end)
    |> Enum.into(%{})
  end

  @doc """
    Check if a contact has more profiles and add that to message.
  """
  def maybe_add_profile_activity(activity_info, contact_id, org_id) do
    {:ok, contact} = Repo.fetch_by(Contact, %{id: contact_id, organization_id: org_id})

    profiles =
      Glific.Profiles.list_profiles(%{filter: %{contact_id: contact.id}, organization_id: org_id})

    profile_activities =
      Enum.reduce(profiles, %{english_messages: [], hindi_messages: []}, fn profile, acc ->
        test_date = profile.fields["test_date"]["value"]
        course = profile.fields["course"]["value"]
        profile_activity = get_activity_info(org_id, test_date, course, "English")
        english_messages = Map.get(acc, :english_messages, [])
        hindi_messages = Map.get(acc, :hindi_messages, [])

        if profile_activity["is_valid"] do
          english_messages = english_messages ++ [profile_activity["activitymainmessageenglish"]]
          hindi_messages = hindi_messages ++ [profile_activity["activitymainmessagehindi"]]

          acc
          |> Map.put(:english_messages, english_messages)
          |> Map.put(:hindi_messages, hindi_messages)
        else
          acc
        end
      end)

    if profile_activities[:english_messages] != [] do
      english_activity_message =
        Map.get(profile_activities, :english_messages, []) |> Enum.join("\n\n")

      hindi_activity_message =
        Map.get(profile_activities, :hindi_messages, []) |> Enum.join("\n\n")

      Map.merge(activity_info, %{
        profiles_activity_message_english: english_activity_message,
        profiles_activity_message_hindi: hindi_activity_message
      })
    else
      activity_info
    end
  end

  @doc """
    Update the fields for all the profiles.
  """
  @spec update_all_profile_fields(non_neg_integer(), non_neg_integer(), String.t(), String.t()) ::
          :ok
  def update_all_profile_fields(org_id, contact_id, key, value) do
    {:ok, contact} = Repo.fetch_by(Contact, %{id: contact_id, organization_id: org_id})

    %{
      filter: %{contact_id: contact.id},
      organization_id: org_id
    }
    |> Glific.Profiles.list_profiles()
    |> Enum.each(fn profile ->
      new_fields = %{
        key => %{
          "inserted_at" => DateTime.utc_now(),
          "value" => value,
          "type" => "string",
          "label" => key
        }
      }

      fields = Map.merge(profile.fields, new_fields)
      Glific.Profiles.update_profile(profile, %{fields: fields})
    end)

    ContactField.do_add_contact_field(contact, key, key, value)
    :ok
  end

  @doc """
  Fix the contact name issue
  """
  @spec fix_contact_name :: :ok
  def fix_contact_name do
    %{
      filter: %{},
      organization_id: 12
    }
    |> Glific.Profiles.list_profiles()
    |> Enum.each(fn profile ->
      fields = profile.fields

      contact_name = %{
        "contact_name" => %{
          "inserted_at" => "2022-08-03T13:43:21.134329Z",
          "value" => profile.name,
          "type" => "string",
          "label" => "contact name"
        },
        "name" => %{
          "inserted_at" => "2022-08-03T13:43:21.134329Z",
          "value" => profile.name,
          "type" => "string",
          "label" => "Name"
        }
      }

      fields = Map.merge(fields, contact_name)
      Glific.Profiles.update_profile(profile, %{fields: fields})
    end)
  end
end
