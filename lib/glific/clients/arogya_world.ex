defmodule Glific.Clients.ArogyaWorld do
  @moduledoc """
  Custom code extenison for ArogyaWorld
  """
  require Logger

  import Ecto.Query

  alias Glific.{
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient,
    Triggers.Trigger,
    Messages.Message,
    GCS.GcsWorker
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

  @static_flow %{
    group_id: 679,
    flow_id: 2500
  }

  @dynamic_flow %{
    group_id: 680,
    flow_id: 2501
  }

  @csv_url_key_map %{
    "static_message_schedule" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Messages.csv",
    "message_template_map" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Messages.csv",
    "question_template_map" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Questions.csv",
    "dynamic_message_schedule_week" =>
      "https://storage.googleapis.com/arogya-sheets/week1_to_participant%20-%20Sheet1.csv"
  }

  @doc """
  Run this function on the initial load
  """
  @spec initial_load(non_neg_integer()) :: any()
  def initial_load(org_id) do
    static_message_schedule_map(@csv_url_key_map["static_message_schedule"])
    message_hsm_mapping(@csv_url_key_map["message_template_map"])
    question_hsm_mapping(@csv_url_key_map["question_template_map"])
    load_participant_file(org_id, 1)
  end

  @spec webhook(String.t(), map) :: map()
  def webhook("static_message", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
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
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

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
      question_template_id: question_template_id || false,
      question_lable: "Q#{current_week_day}_#{question_id}"
    }
  end

  def webhook(_, fields), do: fields
  @spec weekly_tasks(non_neg_integer()) :: any()
  def weekly_tasks(org_id), do: run_weekly_tasks(org_id)

  defp run_weekly_tasks(org_id) do
    {_current_week, next_week} = update_week_number(org_id)
    load_participant_file(org_id, next_week)
  end

  @spec daily_tasks(non_neg_integer()) :: any()
  def daily_tasks(org_id) do
    ## This is just for pilot phase. Will be removed later. We will update the weeknumber on a daily basis.
    run_weekly_tasks(org_id)
  end

  @spec hourly_tasks(non_neg_integer()) :: any()
  def hourly_tasks(org_id) do
    ## This is just for pilot phase. Will be removed later. We will update the day on a hourly basis.
    if is_nil(get_week_day_number()) do
      Logger.info("Weekday is nil. Skipping hourly tasks.")
    else
      broadcast_static_group(org_id)
      broadcast_dynamic_group(org_id)
    end

    ## broadcast for dynamic group
  end

  defp broadcast_static_group(_org_id) do
    static_flow = Glific.Flows.get_flow!(@static_flow.flow_id)
    static_group = Glific.Groups.get_group!(@static_flow.group_id)
    Glific.Flows.start_group_flow(static_flow, static_group)
  end

  defp broadcast_dynamic_group(_org_id) do
    dynamic_flow = Glific.Flows.get_flow!(@dynamic_flow.flow_id)
    dynamic_group = Glific.Groups.get_group!(@dynamic_flow.group_id)
    Glific.Flows.start_group_flow(dynamic_flow, dynamic_group)
  end

  defp get_current_week(organization_id) do
    ## For pilot phase, it will be the day number.
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{organization_id: organization_id, key: "current_week"})

    organization_data.text
  end

  defp get_week_day_number do
    ## For pilot phase, we will use the hour number.
    hour = Timex.now().hour
    @pilot_hour_to_day[hour]

    ## we will enable this when pilot phase is over.
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

    current_week = Glific.parse_maybe_integer!(organization_data.text)

    next_week = current_week + 1

    {:ok, _} =
      Partners.update_organization_data(organization_data, %{
        key: "current_week",
        text: next_week
      })

    {current_week, next_week}
  end

  @doc false
  @spec load_participant_file(non_neg_integer(), non_neg_integer()) :: any()
  def load_participant_file(_org_id, week_number) do
    key = get_dynamic_week_key(week_number)
    add_weekly_dynamic_data(key, @csv_url_key_map["dynamic_message_schedule_week"])
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
    ApiClient.get_csv_content(url: file_url)
    |> Enum.reduce(default_value, fn {_, data}, acc ->
      cleanup_func.(acc, data)
    end)
    |> then(fn data -> maybe_insert_data(key, data) end)
  end

  @doc """
  message mapping to HSM UUID
  """
  @spec message_hsm_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def message_hsm_mapping(file_url) do
    add_data_from_csv("message_template_map", file_url, fn acc, data ->
      Map.put(acc, data["Message ID"], data["Glific Template UUID"])
    end)
  end

  @doc """
  question mapping to HSM UUID
  """
  @spec question_hsm_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def question_hsm_mapping(file_url) do
    add_data_from_csv("question_template_map", file_url, fn acc, data ->
      Map.put(acc, data["Question ID"], data["Glific Template UUID"])
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

    Map.put(acc, data["ID"], attr)
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
      if Map.has_key?(acc, data["Week"]) do
        Map.put(acc[data["Week"]], check_second_day, data["Message ID"])
      else
        %{check_second_day => data["Message ID"]}
      end

    Map.put(acc, data["Week"], week)
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
          |> Map.put(:organization_id, Repo.get_organization_id())

        %OrganizationData{}
        |> OrganizationData.changeset(attrs)
        |> Repo.insert()

      organization_data ->
        organization_data
        |> OrganizationData.changeset(%{json: data})
        |> Repo.update()
    end
  end

  @doc """
  Conditionally execute the trigger based on: ID, Week, Day.
  """
  @spec trigger_condition(Trigger.t()) :: boolean
  def trigger_condition(trigger) do
    if trigger.id > 0,
      do: true,
      else: false
  end

  @doc """
  get the messages based on flow label
  """
  @spec get_messages_by_flow_label(non_neg_integer(), String.t()) :: any()
  def get_messages_by_flow_label(org_id, label) do
    Message
    |> where([m], like(m.flow_label, ^"#{label}%"))
    |> where([m], m.organization_id == ^org_id)
    |> Repo.all()
  end

  @doc """
  Create a file in GCS bucket for candidate response
  """
  @spec response_from_participant(non_neg_integer()) :: any()
  def response_from_participant(org_id) do
    q1_responses =
      get_messages_by_flow_label(org_id, "q_1_")
      |> Enum.map(fn m ->
        %{"ID" => m.contact_id, "Q1_ID" => get_question_id(m.flow_label), "Q1_response" => m.body}
      end)

    q2_responses =
      get_messages_by_flow_label(org_id, "q_4_")
      |> Enum.map(fn m ->
        %{"ID" => m.contact_id, "Q2_ID" => get_question_id(m.flow_label), "Q2_response" => m.body}
      end)

    # merging response
    current_week_responses =
      q1_responses
      |> Enum.map(fn q1 ->
        q2 =
          Enum.find(q2_responses, nil, fn x ->
            x["ID"] === q1["ID"]
          end)

        %{
          "ID" => q1["ID"],
          "Q1_ID" => q1["Q1_ID"],
          "Q1_response" => q1["Q1_response"],
          "Q2_ID" => q2["Q2_ID"],
          "Q2_response" => q2["Q2_response"]
        }
      end)

    temp_path =
      System.tmp_dir!()
      |> Path.join("participant_response.csv")

    file = temp_path |> File.open!([:write, :utf8])

    current_week_responses
    |> CSV.encode(headers: ["ID", "Q1_ID", "Q1_response", "Q2_ID", "Q2_response"])
    |> Enum.each(&IO.write(file, &1))

    current_week = get_current_week(org_id)

    GcsWorker.upload_media(temp_path, "participant_response_week_#{current_week}.csv", org_id)
    |> case do
      {:ok, gcs_url} -> %{url: gcs_url, error: nil}
      {:error, error} -> %{url: nil, error: error}
    end
  end

  @doc """

  """
  @spec get_question_id(String.t()) :: any()
  def get_question_id(label) do
    String.split(label, "_", trim: true)
    |> List.last()
  end
end
