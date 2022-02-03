defmodule Glific.Clients.ArogyaWorld do
  @moduledoc """
  Custom code extenison for ArogyaWorld
  """
  require Logger

  import Ecto.Query

  alias Glific.{
    GCS.GcsWorker,
    Messages.Message,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient,
    Triggers.Trigger
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

  @csv_url_key_map %{
    "static_message_schedule" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Messages.csv",
    "message_template_map" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Messages.csv",
    "question_template_map" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Questions.csv",
    "response_score_map" => "https://storage.googleapis.com/arogya-sheets/score_encoding.csv",
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
    response_score_mapping(@csv_url_key_map["response_score_map"])
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

  @doc """
  Send the response data back to arogya team in a CSV file
  """
  def webhook("send_participant_responses", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    current_week = get_current_week(organization_id)
    upload_participant_responses(organization_id, current_week)
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
      question_label: "Q#{current_week}_#{current_week_day}_#{question_id}"
    }
  end

  def webhook(_, fields), do: fields
  @spec weekly_tasks(non_neg_integer()) :: any()
  def weekly_tasks(org_id), do: run_weekly_tasks(org_id)

  defp run_weekly_tasks(org_id) do
    {_current_week, next_week} = update_week_number(org_id)

    Logger.info(
      "Ran daily tasks for update_week_number for org id: #{org_id}, next week: #{next_week}"
    )

    load_participant_file(org_id, next_week)
  end

  @spec daily_tasks(non_neg_integer()) :: any()
  def daily_tasks(org_id) do
    Logger.info("Ran daily tasks for organization #{org_id}")

    ## This is just for pilot phase. Will be rmoved later. We will update the weeknumber on a daily basis.
    run_weekly_tasks(org_id)
  end

  @spec hourly_tasks(non_neg_integer()) :: any()
  def hourly_tasks(org_id) do
    ## This is just for pilot phase. Will be removed later. We will update the day on a hourly basis.
    if get_week_day_number() === 23 do
      current_week = get_current_week(org_id)
      upload_participant_responses(org_id, current_week)
    end
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

  @spec update_week_number(non_neg_integer()) :: {integer, integer}
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
        text: to_string(next_week)
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
  response to score mapping
  """
  @spec response_score_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def response_score_mapping(file_url) do
    add_data_from_csv("response_score_map", file_url, fn acc, data ->
      Map.put(acc, data["1"], 1)
      |> Map.put(data["2"], 2)
      |> Map.put(data["3"], 3)
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
  Get the messages based on flow label
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
  @spec upload_participant_responses(non_neg_integer(), non_neg_integer()) :: any()
  def upload_participant_responses(org_id, week) do
    # Question 1 responses for current week
    q1_responses =
      get_messages_by_flow_label(org_id, "Q#{week}_1_")
      |> Enum.map(fn m ->
        q1_id = get_question_id(m.flow_label)

        %{
          "ID" => m.contact_id,
          "Q1_ID" => q1_id,
          "Q1_response" => get_response_score(m.body, q1_id, org_id)
        }
      end)

    # Question 2 responses for current week
    q2_responses =
      get_messages_by_flow_label(org_id, "Q#{week}_4_")
      |> Enum.map(fn m ->
        q2_id = get_question_id(m.flow_label)

        %{
          "ID" => m.contact_id,
          "Q2_ID" => q2_id,
          "Q2_response" => get_response_score(m.body, q2_id, org_id)
        }
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

    # Creating a CSV file
    temp_path =
      System.tmp_dir!()
      |> Path.join("participant_response.csv")

    file = temp_path |> File.open!([:write, :utf8])

    current_week_responses
    |> CSV.encode(headers: ["ID", "Q1_ID", "Q1_response", "Q2_ID", "Q2_response"])
    |> Enum.each(&IO.write(file, &1))

    # Upload the file to GCS
    GcsWorker.upload_media(temp_path, "participant_responses_week_#{week}.csv", org_id)
    |> case do
      {:ok, gcs_url} -> %{url: gcs_url, error: nil}
      {:error, error} -> %{url: nil, error: error}
    end
  end

  @doc """
  Return the question id based on the label
  """
  @spec get_question_id(String.t()) :: any()
  def get_question_id(label) do
    String.split(label, "_", trim: true)
    |> List.last()
  end

  @doc """
  Return the response score based on the body
  """
  @spec get_response_score(String.t(), String.t(), non_neg_integer()) :: any()
  def get_response_score(response, q_id, org_id) do
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: org_id,
        key: "response_score_map"
      })

    response_score = organization_data.json

    # Need to add type of question and check from that instead of id
    if q_id == "27" do
      count = String.split(response, ",") |> length()

      cond do
        count === 1 ->
          1

        count > 1 and count < 4 ->
          2

        count === 4 ->
          3

        true ->
          response
      end
    else
      if response_score[response] !== nil do
        response_score[response]
      else
        response
      end
    end
  end
end
