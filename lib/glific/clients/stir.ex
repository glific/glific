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
      %{description: "Creating safe learning environments _(Safety)_", keyword: "1", tdc_survery_flow: "448ef122-d257-42a3-bbd4-dd2d6ff43761"}
    },
    {
      "engagement",
      %{description: "Dedication and engagement _(Engagement)_", keyword: "2", tdc_survery_flow: "06247ce0-d5b7-4a42-b1e9-166dc85e9a74"}
    },
    {
      "c&ct",
      %{description: "Promoting an improvement-focused culture _(Curiosity & Critical Thinking)_", keyword: "3", tdc_survery_flow: "27839001-d31c-4b53-9209-fe25615a655f"}
    },
    {
     "selfesteem",
    %{description: "Improving learning self-esteem (collaborate, recognise achievements/celebrate, and ask for support) _(Self-Esteem)_",
    keyword: "4", tdc_survery_flow: "3f38afbe-cb97-427e-85c0-d1a455952d4c"}
    },
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

    mt_list =
      get_mt_list(fields["district"], organization_id)
      |> Enum.map(fn contact -> "Type *#{contact.index}* for #{contact.name}" end)
      |> Enum.join("\n")

    %{mt_list_message: mt_list}
  end

  def webhook("set_mt_for_tdc", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])
    {:ok, mt_contact_index} = Glific.parse_maybe_integer(fields["mt_contact_id"])

    tdc =  Contacts.get_contact!(contact_id)

    mt =
      get_mt_list(fields["district"], organization_id)
      |> Enum.find(fn contact -> contact.index == mt_contact_index end)

    ## this is not correct we will fix that.
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

    %{message: praority_message}
  end

  def webhook("contact_updated_the_priorities", fields) do
    first_priority = get_in(fields, ["contact", "fields", "first_priority", "value"])
    second_priority = get_in(fields, ["contact", "fields", "second_priority", "value"])
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])

    contact = Contacts.get_contact!(contact_id)

    priority_versions = get_priority_versions(fields)["versions"] || []

    versions =  priority_versions ++ [%{first_priority: first_priority, second_priority: second_priority, updated_at: Date.to_string(Timex.today)}]

    priority_change_map =  %{
      last_priority_change: Date.to_string(Timex.today),
      versions: versions
    }

    priority_versions_as_string = Jason.encode!(priority_change_map)
    ContactField.do_add_contact_field(contact, "priority_versions", "priority_versions", priority_versions_as_string, "json")

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

      if Timex.diff(Timex.today, last_updated_date, :days) <= 30, do: 2, else: 1
    end

      %{frequency: frequency}
  end

  def webhook("priority_based_survery_flows", fields) do
    {:ok, mt_contact_id} = get_in(fields, ["contact", "fields", "mt_contact_id", "value"])
                          |> Glific.parse_maybe_integer()

    contact = Contacts.get_contact!(mt_contact_id)

    first_priority =
        contact.fields["first_priority"]["value"]
        |> clean_string()

    second_priority =
        contact.fields["second_priority"]["value"]
        |> clean_string()

    priority_map =  Enum.into(@priorities_list, %{})
    %{
      first_priority: priority_map[first_priority][:tdc_survery_flow],
      second_priority: priority_map[second_priority][:tdc_survery_flow]
    }

  end

  def webhook("compute_survey_score", %{results: results}),
    do: compute_survey_score(results)


  def webhook(_, fields), do: fields

  defp get_priority_versions(fields) do
    priority_version_field = get_in(fields, ["contact", "fields", "priority_versions", "value"])
    priority_version_field = if priority_version_field in ["", nil], do: "{}", else: priority_version_field
    Jason.decode!(priority_version_field)

  end

  defp clean_string(str) do
    String.downcase(str || "")
    |> String.trim()
  end

  defp get_mt_list(district, organization_id) do
    group_label = district_group(district, :mt)
    {:ok, group} = Repo.fetch_by(Group, %{label: group_label, organization_id: organization_id})
    Contacts.list_contacts(%{filter: %{include_groups: [group.id]}})
    |> Enum.with_index(1)
    |> Enum.map(fn {contact, index} -> %{index: index, name: contact.name, id: contact.id} end)
    |> IO.inspect()
  end

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
