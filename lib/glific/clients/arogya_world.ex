defmodule Glific.Clients.ArogyaWorld do
  require Logger

  alias Glific.{
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient
  }


  @pilot_hour_to_day %{
    3 => 1,
    4 => 2,
    5 => 3,
    6 => 4,
    7 => 5,
    8 => 6,
    9 => 7
  }

  @week_url_map %{
    "dynamic_message_schedule_week_1" =>
      "https://storage.googleapis.com/week1_to_participant%20-%20Sheet1.csv",
    "dynamic_message_schedule_week_2" => "",
    "dynamic_message_schedule_week_3" => "",
    "dynamic_message_schedule_week_4" => ""
  }

  def webhook("static_message", fields) do
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])
    current_week = get_current_week(organization_id)
    current_week_day = get_week_day_number()
    message_id = get_message_id(organization_id, current_week, current_week_day)
    template_id = get_message_template_id(organization_id, message_id)

    %{
      message_id: message_id,
      template_id: template_id || false,
      current_week: current_week,
      current_week_day: current_week_day
    }
  end

  def webhook("dynamic_message", fields) do
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])
    {:ok, contact_id} = Glific.parse_maybe_integer(get_in(fields, ["contact", "id"]))

    current_week = get_current_week(organization_id)
    current_week_day = get_week_day_number()

    message_id =
      get_dynamic_message_id(organization_id, current_week, current_week_day, contact_id)

    question_id =
      get_dynamic_question_id(organization_id, current_week, current_week_day, contact_id)

    message_template_id = get_message_template_id(organization_id, message_id)
    question_template_id = get_question_template_id(organization_id, question_id)

    %{
      current_week: current_week,
      current_week_day: current_week_day,
      message_id: message_id,
      question_id: question_id,
      message_template_id: message_template_id || false,
      question_template_id: question_template_id || false
    }
  end

  def webhook(_, fields), do: fields

  def weekly_tasks(org_id), do: run_weekly_tasks(org_id)

  defp run_weekly_tasks(org_id) do
    {_current_week, next_week} = update_week_number(org_id)
    load_participient_file(org_id, next_week)
  end

  def daily_tasks(org_id) do
    ## This is just for pilot phase. Will be removed later. We will update the weeknumber on a daily basis.
    run_weekly_tasks(org_id)
  end

  def hourly_tasks(org_id) do
    ## This is just for pilot phase. Will be removed later. We will update the day on a hourly basis.
    if(is_nil(get_week_day_number()))
      Logger.info("Weekday is nil. Skipping hourly tasks.")
    else
      broadcast_static_group(org_id)
      broadcast_dynamic_group(org_id)
    end

    ## broadcast for dynamic group
  end

  defp broadcast_static_group(_org_id) do
    static_flow_id = 1
    static_group_id = 1
    static_flow = Glific.Flows.get_flow!(static_flow_id)
    static_group = Glific.Groups.get_group!(static_group_id)
    Glific.Flows.start_group_flow(static_flow, static_group)
  end

  defp broadcast_dynamic_group(_org_id) do
    dynamic_flow_id = 1
    dynamic_group_id = 1
    dynamic_flow = Glific.Flows.get_flow!(dynamic_flow_id)
    dynamic_group = Glific.Groups.get_group!(dynamic_group_id)
    Glific.Flows.start_group_flow(dynamic_flow, dynamic_group)
  end

  defp get_current_week(organization_id) do
    ## For pilot phase, it will be the day number.
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{organization_id: organization_id, key: "current_week"})

    organization_data.text
  end

  defp get_week_day_number() do
    ## For pilot phase, we will use the hour number.
    hour = Timex.now().hour
    @pilot_hour_to_day[hour]
    # Todo: ## we will enable this when pilot phase is over.
    # Timex.weekday(Timex.today())
  end

  defp get_dynamic_week_key(current_week),
    do: "dynamic_message_schedule_week_#{current_week}"

  defp get_message_id(organization_id, current_week, current_week_day) do
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: "static_message_schedule"
      })

    current_week_day = to_string(current_week_day)
    static_message_schedule = organization_data.json
    get_in(static_message_schedule, [current_week, current_week_day])
  end

  defp get_message_template_id(organization_id, message_id) do
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: "message_template_map"
      })

    message_id = to_string(message_id)

    message_template_map = organization_data.json
    get_in(message_template_map, [message_id])
  end

  defp get_question_template_id(organization_id, question_id) do
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: "question_template_map"
      })

    question_id = to_string(question_id)

    question_template_map = organization_data.json
    get_in(question_template_map, [question_id])
  end

  defp get_dynamic_message_id(organization_id, current_week, current_week_day, contact_id) do
    key = get_dynamic_week_key(current_week)

    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: key
      })

    current_week_day = to_string(current_week_day)
    dynamic_message_schedule = organization_data.json
    contact_id = to_string(contact_id)
    get_in(dynamic_message_schedule, [contact_id, current_week_day, "m_id"])
  end

  defp get_dynamic_question_id(organization_id, current_week, current_week_day, contact_id) do
    key = get_dynamic_week_key(current_week)

    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: key
      })

    contact_id = to_string(contact_id)
    current_week_day = to_string(current_week_day)
    dynamic_message_schedule = organization_data.json

    get_in(dynamic_message_schedule, [contact_id, current_week_day, "q_id"])
  end

  defp update_week_number(org_id) do
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: org_id,
        key: "current_week"
      })

    {:ok, current_week} = Glific.parse_maybe_integer(organization_data.text)

    next_week = current_week + 1

    {:ok, _} =
      Partners.update_organization_data(organization_data, %{
        key: "current_week",
        text: next_week
      })

    {current_week, next_week}
  end

  def load_participient_file(_org_id, week_number) do
    key = get_dynamic_week_key(week_number)
    add_weekly_dynamic_data(key, @week_url_map[key])
  end

  @doc """
    get template form EEx
  """
  @spec template(integer(), String.t()) :: binary
  def template(template_uuid, name) do
    %{
      uuid: template_uuid,
      name: name,
      variables: ["@contact.name"],
      expression: nil
    }
    |> Jason.encode!()
  end

  @doc """
  adds the weekly dynamic data loaded from the sheet based on current week
  """
  @spec add_weekly_dynamic_data(String.t(), String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def add_weekly_dynamic_data(key, file_url) do
    add_data_from_csv(
      key,
      file_url,
      &cleanup_week_data/2
    )
  end

  @doc """
  creates the static data map that needs to be sent to users
  """
  @spec static_message_schedule_map(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def static_message_schedule_map(file_url) do
    add_data_from_csv(
      "static_message_schedule",
      file_url,
      &cleanup_static_data/2
    )
  end

  @doc """
  add data that needs to be sent to the database
  """
  @spec add_data_from_csv(String.t(), String.t(), any(), map()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def add_data_from_csv(key, file_url, cleanup_func, default_value \\ %{}) do
    # how to validate if the data is in correct format
    data =
      ApiClient.get_csv_content(url: file_url)
      |> Enum.reduce(default_value, fn {_, data}, acc ->
        cleanup_func.(acc, data)
      end)

    maybe_insert_data(key, data)
  end

  @doc """
  message mapping to HSM UUID
  """
  @spec message_hsm_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def message_hsm_mapping(file_url) do
    add_data_from_csv("message_template_map", file_url, fn acc, data ->
      acc
      |> Map.put_new(data["Message ID"], data["Glific Template UUID"])
    end)
  end

  @doc """
  question mapping to HSM UUID
  """
  @spec question_hsm_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def question_hsm_mapping(file_url) do
    add_data_from_csv("question_template_map", file_url, fn acc, data ->
      acc
      |> Map.put_new(data["Question ID"], data["Glific Template UUID"])
    end)
  end

  @doc """
  Clean week data from the CSV file.
  """
  @spec cleanup_week_data(map(), map()) :: map()
  def cleanup_week_data(acc, data) do
    attr = %{
      "1" => %{
        "q_id" => data["Q1_ID"],
        "m_id" => data["M1_ID"]
      },
      "4" => %{
        "q_id" => data["Q2_ID"],
        "m_id" => data["M2_ID"]
      }
    }

    acc
    |> Map.put_new(data["ID"], attr)
  end

  @doc """
  Clean static weekly data from the CSV file.
  """
  @spec cleanup_static_data(map(), map()) :: map()
  def cleanup_static_data(acc, data) do
    # check for 2nd day and update it to 4th
    check_second_day =
      if data["Message No"] === "2",
        do: "4",
        else: data["Message No"]

    week =
      if(Map.has_key?(acc, data["Week"])) do
        acc[data["Week"]] |> Map.put(check_second_day, data["Message ID"])
      else
        %{check_second_day => data["Message ID"]}
      end

    acc
    |> Map.put(data["Week"], week)
  end

  @doc """
  Insert or update data if key present for OrganizationData table.
  """
  @spec maybe_insert_data(String.t(), map()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
  def maybe_insert_data(key, data) do
    # check if the week key is already present in the database
    case Repo.get_by(OrganizationData, %{key: key}) do
      nil ->
        attrs =
          %{}
          |> Map.put(:key, key)
          |> Map.put(:json, data)
          |> Map.put(:organization_id, 1)

        %OrganizationData{}
        |> OrganizationData.changeset(attrs)
        |> Repo.insert()

      organization_data ->
        organization_data
        |> OrganizationData.changeset(%{json: data})
        |> Repo.update()
    end
  end
end
