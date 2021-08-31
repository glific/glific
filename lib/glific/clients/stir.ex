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
        mt_feedback_videos: %{
          rank_a: "Video 1",
          rank_b: "Video 2",
          rank_c: "Video 3"
        }
      }
    },
    {
      "engagement",
      %{
        description: "Dedication and engagement _(Engagement)_",
        keyword: "2",
        tdc_survery_flow: "06247ce0-d5b7-4a42-b1e9-166dc85e9a74",
        mt_feedback_videos: %{
          rank_a: "Video 4",
          rank_b: "Video 5",
          rank_c: "Video 6"
        }
      }
    },
    {
      "c&ct",
      %{
        description: "Promoting an improvement-focused culture _(Curiosity & Critical Thinking)_",
        keyword: "3",
        tdc_survery_flow: "27839001-d31c-4b53-9209-fe25615a655f",
        mt_feedback_videos: %{
          rank_a: "Video 7",
          rank_b: "Video 8",
          rank_c: "Video 9"
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
        mt_feedback_videos: %{
          rank_a: "Video 10",
          rank_b: "Video 11",
          rank_c: "Video 12"
        }
      }
    }
  ]

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

    contact_priorities = get_contact_priority(get_in(fields, ["contact", "fields"]))

    first_priority =
      contact_priorities.first
      |> clean_string()

    second_priority =
      contact_priorities.second
      |> clean_string()

    first_priority_map = Map.get(priority_map, first_priority, %{})
    second_priority_map = Map.get(priority_map, second_priority, %{})

    %{
      first_priority_description: first_priority_map[:description] || "NA",
      second_priority_description: second_priority_map[:description] || "NA"
    }
  end

  def webhook("contact_updated_the_priorities", fields) do
    first_priority = get_in(fields, ["contact", "fields", "first_priority", "value"])
    second_priority = get_in(fields, ["contact", "fields", "second_priority", "value"])
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])

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
      mt_priorities = get_contact_priority(contact.fields)

      first_priority =
        mt_priorities.first
        |> clean_string()

      second_priority =
        mt_priorities.second
        |> clean_string()

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

    mt_priorities =
      get_in(fields, ["contact", "fields"])
      |> get_contact_priority()

    result = %{
      district: mt_district,
      mt_first_priority: mt_priorities.first,
      mt_second_priority: mt_priorities.second,
      diet_first_priority: "NA",
      diet_second_priority: "NA"
    }

    get_diet_list(fields["diet_group"], organization_id)
    |> Enum.find(fn {district, _contact} -> district == mt_district end)
    |> case do
      {_district, diet} ->
        diet_priorities = get_contact_priority(diet.fields)

        Map.merge(
          result,
          %{
            diet_first_priority: diet_priorities.first,
            diet_second_priority: diet_priorities.second
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
    save_survey_results(contact, fields, mt_type(fields))
  end

  def webhook("get_survey_results", fields),
    do: get_survey_results(fields, mt_type(fields))

  def webhook("compute_survey_score", %{results: results}),
    do: compute_survey_score(results)

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

  @spec get_survey_results(map(), atom()) :: map()
  defp get_survey_results(fields, :TYPE_A) do
    option_a_data = get_option_a_data(fields)

    contact_priorities =
      get_in(fields, ["contact", "fields"])
      |> get_contact_priority()

    first_priority =
      contact_priorities.first
      |> clean_string()

    second_priority =
      contact_priorities.second
      |> clean_string()

    %{
      option_a_data: option_a_data,
      first_priority: first_priority,
      second_priority: second_priority,
      first_priority_rank: option_a_data[first_priority]["least_rank"],
      second_priority_rank: option_a_data[second_priority]["least_rank"]
    }
  end

  defp get_survey_results(fields, :TYPE_B) do
    option_b_data = get_option_b_data(fields)

    contact_priorities =
      get_in(fields, ["contact", "fields"])
      |> get_contact_priority()

    first_priority =
      contact_priorities.first
      |> clean_string()

    second_priority =
      contact_priorities.second
      |> clean_string()

    p1_answers = option_b_data[first_priority]["answers"]
    p2_answers = option_b_data[second_priority]["answers"]

    %{
      option_b_data: option_b_data,
      first_priority: first_priority,
      second_priority: second_priority,
      first_priority_answers: p1_answers,
      second_priority_answers: p2_answers,
      should_send_all: is_all_the_answers_true?(p1_answers, p2_answers)
    }
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

  @spec is_all_the_answers_true?(map(), map()) :: boolean()
  defp is_all_the_answers_true?(ans1, ans2) do
    answer_list = Map.values(ans1) ++ Map.values(ans2)

    cond do
      "0-33" in answer_list ->
        false

      "34-66" in answer_list ->
        false

      true ->
        true
    end
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
