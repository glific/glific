defmodule Glific.Clients.Stir do
  @moduledoc """
  Example implementation of survey computation for STiR
  Glific.Clients.Stir.compute_art_content(res)
  """

  alias Glific.{
    Contacts,
    Flows.ContactField,
    Groups,
    Groups.Group,
    Repo
  }

  @priorities_list [
    {
      "safety",
      %{
        description: "Creating safe learning environments _(Safety)_",
        keyword: "1",
        tdc_survery_flow: "448ef122-d257-42a3-bbd4-dd2d6ff43761",
        option_b_videos: %{
          "s1" => %{
            code: :s1,
            title: "More reflective discussion on the strategy"
          },
          "s2" => %{
            code: :s2,
            title: "Participants' get improvement focused feedback"
          },
          "s3" => %{
            code: :s3,
            title: "Space for practising the strategy"
          },
          "s4" => %{
            code: :s4,
            title: "Participants referring to data"
          }
        }
      }
    },
    {
      "engagement",
      %{
        description: "Dedication and engagement _(Engagement)_",
        keyword: "2",
        tdc_survery_flow: "06247ce0-d5b7-4a42-b1e9-166dc85e9a74",
        option_b_videos: %{
          "s1" => %{
            code: :e1,
            title: "Proactive participation"
          },
          "s2" => %{
            code: :e2,
            title: "Developing action plans"
          },
          "s3" => %{
            code: :e3,
            title: "Asking questions"
          }
        }
      }
    },
    {
      "c&ct",
      %{
        description: "Promoting an improvement-focused culture _(Curiosity & Critical Thinking)_",
        keyword: "3",
        tdc_survery_flow: "27839001-d31c-4b53-9209-fe25615a655f",
        option_b_videos: %{
          "s1" => %{
            code: :c1,
            title: "Reflect on the content link to purpose"
          },
          "s2" => %{
            code: :c2,
            title: "Asking 'how' questions"
          },
          "s3" => %{
            code: :c3,
            title: "Asking 'why' questions"
          }
        }
      }
    },
    {
      "selfesteem",
      %{
        description:
          "Improving learning self-esteem (collaborate, recognise achievements/celebrate, and ask for support) _(Self-Esteem)_",
        keyword: "4",
        tdc_survery_flow: "3f38afbe-cb97-427e-85c0-d1a455952d4c",
        option_b_videos: %{
          "s1" => %{
            code: :se1,
            title: "Collaborating with peers"
          },
          "s2" => %{
            code: :se2,
            title: "Asking for support"
          },
          "s3" => %{
            code: :se3,
            title: "Achievements recognized"
          }
        }
      }
    }
  ]

  @intentional_coach_survey_titles %{
    "question_1" => "provide inputs without prompting",
    "question_2" => "link actions to wider purpose",
    "question_3" => "list action points to take forward",
    "question_4" => "problem solving and discussion",
    "question_5" => "ask why and who questions"
  }

  @doc false
  @spec webhook(String.t(), map()) :: map()
  def webhook("move_mt_to_district_group", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])
    group_label = district_group(fields["district"], :mt)
    {:ok, group} = Groups.get_or_create_group_by_label(group_label, organization_id)

    Groups.create_contact_group(%{
      contact_id: contact_id,
      group_id: group.id,
      organization_id: organization_id
    })

    %{group: group.label, is_moved: true}
  end

  def webhook("fetch_mt_list", fields) do
    # {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])

    mt_list = get_mt_list(fields["district"], organization_id)

    {index_map, message_list} =
      Enum.reduce(mt_list, {%{}, []}, fn {contact, index}, {index_map, message_list} ->
        contact_name = get_in(contact.fields, ["name", "value"]) || contact.name

        {
          Map.put(index_map, index, contact.id),
          message_list ++ ["Type *#{index}* for #{contact_name}"]
        }
      end)

    %{mt_list_message: Enum.join(message_list, "\n"), index_map: Jason.encode!(index_map)}
  end

  def webhook("fetch_remaining_priorities", fields) do
    priority_map = Enum.into(@priorities_list, %{})
    first_priority = fields["first_priority"] |> String.downcase()
    second_priority = fields["second_priority"] |> String.downcase()

    [remaining_priority_first, remaining_priority_second | _] =
      priority_map
      |> Map.delete(first_priority)
      |> Map.delete(second_priority)
      |> Map.keys()

    %{
      remaining_priority_first: remaining_priority_first,
      remaining_priority_second: remaining_priority_second
    }
  end

  def webhook("check_coach_response", fields) do
    filtered_list =
      fields["response"]
      |> Enum.reject(fn {_question_no, response} -> clean_string(response) != "no" end)

    coach_survey_state =
      cond do
        length(filtered_list) == 1 -> "one_no"
        length(filtered_list) > 1 -> "more_than_one_no"
        true -> "all_yes"
      end

    coach_survey_titles = get_coach_survey_titles(coach_survey_state, filtered_list)
    %{coach_survey_state: coach_survey_state, coach_survey_titles: coach_survey_titles}
  end

  def webhook("get_coach_preferred_video", fields) do
    {index_map, _message_list} =
      fields["coach_survey_titles"]
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, []}, fn {data, index}, {index_map, message_list} ->
        {
          Map.put(index_map, index, data),
          message_list ++ [data]
        }
      end)

    {:ok, preference} = Glific.parse_maybe_integer(fields["preference"])
    %{response: index_map[preference]}
  end

  def webhook("set_mt_for_tdc", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])
    index_map = Jason.decode!(fields["index_map"])

    {:ok, mt_contact_id} =
      Map.get(index_map, fields["mt_contact_id"], 0)
      |> Glific.parse_maybe_integer()

    tdc = Contacts.get_contact!(contact_id)

    {mt, _index} =
      get_mt_list(fields["district"], organization_id)
      |> Enum.find(fn {contact, _index} -> mt_contact_id == contact.id end)

    ## this is not the best way to update the contact variables we will fix that after this assignments.
    tdc
    |> ContactField.do_add_contact_field("mt_name", "mt_name", mt.name, "string")
    |> ContactField.do_add_contact_field("mt_contact_id", "mt_contact_id", mt.id, "string")

    %{selected_mt: mt.name}
  end

  def webhook("get_priority_message", fields) do
    exculde = clean_string(fields["exclude"])

    priorities =
      if exculde in [""],
        do: @priorities_list,
        else: Enum.reject(@priorities_list, fn {priority, _} -> exculde == priority end)

    praority_message =
      priorities
      |> Enum.map(fn {_priority, obj} -> "*#{obj.keyword}*. #{obj.description}" end)
      |> Enum.join("\n")

    priority_map = Enum.into(@priorities_list, %{})

    %{message: praority_message, exculde: priority_map[exculde]}
  end

  def webhook("get_priority_descriptions", fields) do
    priority_map = Enum.into(@priorities_list, %{})

    {first_priority, second_priority} =
      get_in(fields, ["contact", "fields"])
      |> cleaned_contact_priority()

    first_priority_map = Map.get(priority_map, first_priority, %{})
    second_priority_map = Map.get(priority_map, second_priority, %{})

    %{
      first_priority_description: first_priority_map[:description] || "NA",
      second_priority_description: second_priority_map[:description] || "NA"
    }
  end

  def webhook("contact_updated_the_priorities", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])

    {first_priority, second_priority} =
      get_in(fields, ["contact", "fields"])
      |> cleaned_contact_priority()

    contact = Contacts.get_contact!(contact_id)

    priority_versions = get_priority_versions(fields)["versions"] || []

    versions =
      priority_versions ++
        [
          %{
            first_priority: first_priority,
            second_priority: second_priority,
            updated_at: Date.to_string(Timex.today())
          }
        ]

    priority_change_map = %{
      last_priority_change: Date.to_string(Timex.today()),
      versions: versions
    }

    priority_versions_as_string = Jason.encode!(priority_change_map)

    ContactField.do_add_contact_field(
      contact,
      "priority_versions",
      "priority_versions",
      priority_versions_as_string,
      "json"
    )

    %{update: true}
  end

  def webhook("priority_selection_frequency", fields) do
    last_priority_change = get_priority_versions(fields)["last_priority_change"]

    frequency =
      if is_nil(last_priority_change) do
        1
      else
        last_updated_date =
          Timex.parse!(last_priority_change, "{YYYY}-{0M}-{D}")
          |> Timex.to_date()

        if Timex.diff(Timex.today(), last_updated_date, :days) <= 30, do: 2, else: 1
      end

    %{frequency: frequency}
  end

  def webhook("priority_based_survery_flows", fields) do
    {:ok, mt_contact_id} =
      get_in(fields, ["contact", "fields", "mt_contact_id", "value"])
      |> Glific.parse_maybe_integer()

    if mt_contact_id <= 0 do
      %{
        first_priority: "NA",
        second_priority: "NA",
        first_priority_flow: "NA",
        second_priority_flow: "NA"
      }
    else
      contact = Contacts.get_contact!(mt_contact_id)

      {first_priority, second_priority} =
        contact.fields
        |> cleaned_contact_priority()

      priority_map = Enum.into(@priorities_list, %{})
      first_priority_map = priority_map[first_priority] || %{}
      second_priority_map = priority_map[second_priority] || %{}

      %{
        first_priority: first_priority,
        second_priority: second_priority,
        first_priority_flow: first_priority_map[:tdc_survery_flow],
        second_priority_flow: second_priority_map[:tdc_survery_flow]
      }
    end
  end

  def webhook("mt_and_diet_priority", fields) do
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])
    mt_district = fields["district"] |> clean_string()

    {first_priority, second_priority} =
      get_in(fields, ["contact", "fields"])
      |> cleaned_contact_priority()

    result = %{
      district: mt_district,
      mt_first_priority: first_priority,
      mt_second_priority: second_priority,
      diet_first_priority: "NA",
      diet_second_priority: "NA"
    }

    get_diet_list(fields["diet_group"], organization_id)
    |> Enum.find(fn {district, _contact} -> district == mt_district end)
    |> case do
      {_district, diet} ->
        {first_priority, second_priority} =
          diet.fields
          |> cleaned_contact_priority()

        Map.merge(
          result,
          %{
            diet_first_priority: first_priority,
            diet_second_priority: second_priority
          }
        )

      _ ->
        result
    end
  end

  def webhook("reset_contact_fields", fields) do
    {:ok, _organization_id} = Glific.parse_maybe_integer(fields["organization_id"])
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])

    Contacts.get_contact!(contact_id)
    |> Contacts.update_contact(%{fields: %{}})

    %{status: true}
  end

  def webhook("save_survey_answer", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    contact = Contacts.get_contact!(contact_id)

    if remaining_priority?(fields["priority"], contact),
      do: %{},
      else: save_survey_results(contact, fields, mt_type(fields))
  end

  def webhook("get_survey_results", fields),
    do: get_survey_results(fields, mt_type(fields))

  def webhook("compute_survey_score", %{results: results}),
    do: compute_survey_score(results)

  def webhook("get_option_b_video_data", fields) do
    index_map = Jason.decode!(fields["index_map"])
    index = fields["index"]

    if Map.has_key?(index_map, index) do
      Map.get(index_map, index)
      |> Map.put("is_valid", true)
    else
      %{"is_valid" => false}
    end
  end

  def webhook(_, fields), do: fields

  # Get MT type if it's A or B and perform the action based on that.
  @spec mt_type(map()) :: atom()
  defp mt_type(fields) do
    contact_state =
      get_in(fields, ["contact", "fields", "state", "value"])
      |> clean_string()

    if contact_state in ["karnataka", "tamilnadu", "tamil nadu"],
      do: :TYPE_B,
      else: :TYPE_A
  end

  @spec remaining_priority?(String.t(), Contacts.Contact.t()) :: boolean()
  defp remaining_priority?(priority, contact) when is_binary(priority) == true do
    {first_priority, second_priority} =
      contact.fields
      |> cleaned_contact_priority()

    clean_string(priority) not in [first_priority, second_priority]
  end

  defp remaining_priority?(_priority, _contact), do: true

  @spec save_survey_results(Contacts.Contact.t(), map(), atom()) :: map()
  defp save_survey_results(contact, fields, :TYPE_A) do
    priority = clean_string(fields["priority"])
    answer = clean_string(fields["answer"])
    least_rank = get_least_rank(fields["answer"])
    option_a_data = get_option_a_data(fields)

    ## reset the value if the survey has been field eariler
    option_a_data = if Map.keys(option_a_data) |> length > 1, do: %{}, else: option_a_data

    priority_item = %{
      "priority" => priority,
      "answer" => answer,
      "least_rank" => least_rank
    }

    option_a_data = Map.put(option_a_data, priority, priority_item)

    contact
    |> ContactField.do_add_contact_field(
      "option_a_data",
      "option_a_data",
      Jason.encode!(option_a_data),
      "json"
    )

    option_a_data
  end

  defp save_survey_results(contact, fields, :TYPE_B) do
    priority = clean_string(fields["priority"])
    answer_s1 = clean_string(fields["answers"]["s1"])
    answer_s2 = clean_string(fields["answers"]["s2"])
    answer_s3 = clean_string(fields["answers"]["s3"])
    option_b_data = get_option_b_data(fields)

    ## reset the value if the survey has been field eariler
    option_b_data = if Map.keys(option_b_data) |> length > 1, do: %{}, else: option_b_data

    priority_item = %{
      "priority" => priority,
      "answers" => %{
        s1: answer_s1,
        s2: answer_s2,
        s3: answer_s3
      }
    }

    option_b_data = Map.put(option_b_data, priority, priority_item)

    contact
    |> ContactField.do_add_contact_field(
      "option_b_data",
      "option_b_data",
      Jason.encode!(option_b_data),
      "json"
    )

    option_b_data
  end

  @spec get_coach_survey_titles(String.t(), list()) :: String.t()
  defp get_coach_survey_titles("all_yes", _response) do
    @intentional_coach_survey_titles
    |> Enum.reduce("", fn {question_no, question}, acc ->
      acc <> String.replace(question_no, "question_", "") <> ". #{question}" <> "\n"
    end)
  end

  defp get_coach_survey_titles("more_than_one_no", response) do
    response
    |> Enum.with_index(1)
    |> Enum.reduce("", fn {{question_no, _answer}, index}, acc ->
      acc <> "#{index}. " <> Map.get(@intentional_coach_survey_titles, question_no) <> "\n"
    end)
  end

  defp get_coach_survey_titles("one_no", response) do
    [{question_no, _answer}] = response
    Map.get(@intentional_coach_survey_titles, question_no)
  end

  @spec get_survey_results(map(), atom()) :: map()
  defp get_survey_results(fields, :TYPE_A) do
    option_a_data = get_option_a_data(fields)

    {first_priority, second_priority} =
      get_in(fields, ["contact", "fields"])
      |> cleaned_contact_priority()

    %{
      option_a_data: option_a_data,
      first_priority: first_priority,
      second_priority: second_priority,
      first_priority_rank: option_a_data[first_priority]["least_rank"],
      second_priority_rank: option_a_data[second_priority]["least_rank"]
    }
  end

  defp get_survey_results(fields, :TYPE_B) do
    {first_priority, second_priority} =
      get_in(fields, ["contact", "fields"])
      |> cleaned_contact_priority()

    option_b_data = get_option_b_data(fields)
    p1_answers = option_b_data[first_priority]["answers"]
    p2_answers = option_b_data[second_priority]["answers"]
    answer_state = option_b_answer_state(p1_answers, p2_answers)

    list_p1 = option_b_video_data(first_priority, p1_answers, answer_state, fields)
    list_p2 = option_b_video_data(second_priority, p2_answers, answer_state, fields)

    {index_map, message_list} =
      (list_p1 ++ list_p2)
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, []}, fn {data, index}, {index_map, message_list} ->
        {
          Map.put(index_map, index, data),
          message_list ++ ["Video *#{index}* for #{data.title}"]
        }
      end)

    %{
      index_map: Jason.encode!(index_map),
      video_message: Enum.join(message_list, "\n"),
      answer_state: option_b_answer_state(p1_answers, p2_answers),
      first_priority: first_priority,
      second_priority: second_priority,
      first_priority_answers: p1_answers,
      second_priority_answers: p2_answers,
      one_video_data: hd(list_p1 ++ list_p2)
    }
  end

  @spec option_b_video_data(String.t(), map(), String.t(), map()) :: list()
  defp option_b_video_data(priority, answers, answer_state, fields) do
    priority_map = Enum.into(@priorities_list, %{})

    Enum.reduce(answers, [], fn {key, value}, acc ->
      if answer_state == "all_true" || value not in ["67-100"] do
        key =
          if is_dam_dmpc_activity?(priority, fields) and key in ["s3", "s4"],
            do: "s4",
            else: key

        item =
          get_in(priority_map, [priority, :option_b_videos, key])
          |> Map.put(:priority, priority)

        [item] ++ acc
      else
        acc
      end
    end)
  end

  defp is_dam_dmpc_activity?("safety", fields) do
    activty =
      get_in(fields, ["contact", "fields", "activity", "value"])
      |> clean_string()

    String.contains?(activty, ["dam", "dmpc"])
  end

  defp is_dam_dmpc_activity?(_priority, _activity), do: false

  @spec option_b_answer_state(map(), map()) :: String.t()
  defp option_b_answer_state(p1_answers, p2_answers) do
    filtered_list =
      (Map.values(p1_answers) ++ Map.values(p2_answers))
      |> Enum.reject(fn answer -> answer == "67-100" end)

    cond do
      length(filtered_list) == 1 -> "one_true"
      length(filtered_list) > 1 -> "more_then_one_true"
      true -> "all_true"
    end
  end

  @spec get_least_rank(String.t()) :: String.t()
  defp get_least_rank(answer) do
    clean_string(answer)
    |> String.split(",", trim: true)
    |> List.last()
  end

  @spec get_priority_versions(map()) :: map()
  defp get_priority_versions(fields) do
    priority_version_field = get_in(fields, ["contact", "fields", "priority_versions", "value"])

    priority_version_field =
      if priority_version_field in ["", nil], do: "{}", else: priority_version_field

    Jason.decode!(priority_version_field)
  end

  @spec get_option_a_data(map()) :: map()
  defp get_option_a_data(fields),
    do: do_get_option(fields, "option_a_data")

  ## We will merge these two functions once we know that there is no other requirnment.
  @spec get_option_b_data(map()) :: map()
  defp get_option_b_data(fields),
    do: do_get_option(fields, "option_b_data")

  @spec do_get_option(map(), String.t()) :: map()
  defp do_get_option(fields, key) do
    option_data = get_in(fields, ["contact", "fields", key, "value"])
    option_data = if option_data in ["", nil], do: "{}", else: option_data
    Jason.decode!(option_data)
  end

  @spec clean_string(String.t()) :: String.t()
  defp clean_string(str) do
    String.downcase(str || "")
    |> String.trim()
  end

  @spec get_contact_priority(map()) :: map()
  defp get_contact_priority(fields) do
    first_priority_map = Map.get(fields, "first_priority", %{})
    second_priority_map = Map.get(fields, "second_priority", %{})

    %{
      first: first_priority_map["value"] || "NA",
      second: second_priority_map["value"] || "NA"
    }
  end

  @spec get_diet_list(String.t(), non_neg_integer()) :: list()
  defp get_diet_list(diet_group_label, organization_id) do
    {:ok, diet_group} =
      Repo.fetch_by(Group, %{label: diet_group_label, organization_id: organization_id})

    Contacts.list_contacts(%{
      filter: %{include_groups: [diet_group.id]},
      opts: %{"order" => "ASC"}
    })
    |> Enum.map(fn contact ->
      district =
        contact.fields["district"]["value"]
        |> clean_string()

      {district, contact}
    end)
  end

  @spec get_mt_list(String.t(), non_neg_integer()) :: list()
  defp get_mt_list(district, organization_id) do
    group_label = district_group(district, :mt)

    Repo.fetch_by(Group, %{label: group_label, organization_id: organization_id})
    |> case do
      {:ok, group} ->
        Contacts.list_contacts(%{filter: %{include_groups: [group.id]}, opts: %{"order" => "ASC"}})
        |> Enum.with_index(1)

      _ ->
        []
    end
  end

  @spec district_group(String.t(), atom()) :: String.t()
  defp district_group(district, :mt) when is_binary(district) do
    district =
      String.trim(district)
      |> String.downcase()

    "MT-#{district}"
  end

  defp district_group(_, _), do: nil

  defp cleaned_contact_priority(fields) do
    contact_priorities = get_contact_priority(fields)

    first_priority =
      contact_priorities.first
      |> clean_string()

    second_priority =
      contact_priorities.second
      |> clean_string()

    {first_priority, second_priority}
  end

  @doc false
  @spec blocked?(String.t()) :: boolean
  def blocked?(phone) do
    pattern = :binary.compile_pattern(["91", "1", "44", "256"])

    if String.starts_with?(phone, pattern),
      do: false,
      else: true
  end

  @spec get_value(String.t(), map()) :: integer()
  defp get_value(k, v) do
    k = String.downcase(k)

    input =
      if is_binary(v["input"]),
        do: String.downcase(v["input"]),
        else: ""

    if input == "y" do
      case k do
        "a1" -> 1
        "a2" -> 2
        "a3" -> 4
        "a4" -> 8
        "a5" -> 16
        _ -> 0
      end
    else
      0
    end
  end

  @spec get_art_content(String.t(), map()) :: String.t()
  defp get_art_content(k, v) do
    k = String.downcase(k)

    if(is_binary(v["input"]), do: String.downcase(v["input"]), else: "")
    |> process(k)
  end

  @spec process(String.t(), String.t()) :: String.t()
  defp process("n", "a1"), do: " *1*. More reflective discussion on the teaching strategy \n"
  defp process("n", "a2"), do: " *2*. Space for practicing a classroom strategy \n"
  defp process("n", "a3"), do: " *3*. Teachers get improvement focused feedback \n"
  defp process("n", "a4"), do: " *4*. Teachers participation \n"
  defp process("n", "a5"), do: " *5*. Developing concrete action plans \n"
  defp process("n", "a6"), do: " *6*. Teachers asking question \n"
  defp process(_, _), do: ""

  @doc """
  Return art content
  """
  @spec compute_art_content(map()) :: String.t()
  def compute_art_content(results) do
    results
    |> Enum.reduce(" ", fn {k, v}, acc ->
      "#{acc} #{get_art_content(k, v)}"
    end)
  end

  @doc """
  Return integer depending on number of n as response in messages
  """
  @spec compute_art_results(map()) :: non_neg_integer()
  def compute_art_results(results) do
    answers =
      results
      |> Enum.map(fn {_k, v} ->
        if is_binary(v["input"]),
          do: String.downcase(v["input"]),
          else: ""
      end)
      |> Enum.reduce(%{}, fn x, acc -> Map.update(acc, x, 1, &(&1 + 1)) end)

    cond do
      is_nil(Map.get(answers, "n")) -> 3
      Map.get(answers, "n") == 1 -> 1
      Map.get(answers, "n") > 1 -> 2
      true -> 3
    end
  end

  @doc """
  Return total score
  """
  @spec compute_survey_score(map()) :: map()
  def compute_survey_score(results) do
    results
    |> Enum.reduce(
      0,
      fn {k, v}, acc -> acc + get_value(k, v) end
    )
    |> get_content()
  end

  @spec get_content(integer()) :: map()
  defp get_content(score) do
    {status, content} =
      cond do
        rem(score, 7) == 0 -> {1, "Your score: #{score} is divisible by 7"}
        rem(score, 5) == 0 -> {2, "Your score: #{score} is divisible by 5"}
        rem(score, 3) == 0 -> {3, "Your score: #{score} is divisible by 3"}
        rem(score, 2) == 0 -> {4, "Your score: #{score} is divisible by 2"}
        true -> {5, "Your score: #{score} is not divisible by 2, 3, 5 or 7"}
      end

    %{
      status: to_string(status),
      content: content,
      score: to_string(score)
    }
  end
end
