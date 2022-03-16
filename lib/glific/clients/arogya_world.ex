defmodule Glific.Clients.ArogyaWorld do
  @moduledoc """
  Custom code extenison for ArogyaWorld
  """
  require Logger

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    GCS.GcsWorker,
    Messages.Message,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient,
    Triggers.Trigger
  }

  @response_sheet_headers ["ID", "Q1_ID", "Q1_response", "Q2_ID", "Q2_response"]

  @first_question_day "3"

  @second_question_day "7"

  @csv_url_key_map %{
    "static_message_schedule" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Messages.csv",
    "message_template_map" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Messages.csv",
    "question_template_map" =>
      "https://storage.googleapis.com/arogya-sheets/Arogya%20message%20HSM%20id's%20-%20Questions.csv",
    "response_score_map" => "https://storage.googleapis.com/arogya-sheets/score_encoding.csv",
    "dynamic_message_schedule_week" =>
      "https://storage.googleapis.com/participant-files/uploads/to_participants_week_"
  }

  @doc """
  Run this function on the initial load
  """
  @spec initial_load(non_neg_integer()) :: any()
  def initial_load(org_id) do
    dynamic_week_start = 2
    static_message_schedule_map(@csv_url_key_map["static_message_schedule"], org_id)
    message_hsm_mapping(@csv_url_key_map["message_template_map"], org_id)
    question_hsm_mapping(@csv_url_key_map["question_template_map"], org_id)
    response_score_mapping(@csv_url_key_map["response_score_map"], org_id)
    load_participant_file(org_id, dynamic_week_start)
  end

  @doc """
  Webhook functions for the ArogyaWorld
  """
  @spec webhook(String.t(), map) :: map()
  def webhook("static_message", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    current_week = get_current_week(organization_id, contact_id)

    current_week_day = get_week_day_number()
    message_id = get_message_id(organization_id, current_week, current_week_day)
    template_id = get_message_template_id(organization_id, message_id)

    %{
      message_id: message_id,
      template_id: template_id || false,
      current_week: current_week,
      current_week_day: current_week_day,
      message_label: "static_message_#{current_week}_#{current_week_day}"
    }
  end

  def webhook("batch_current_week", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    contact_id = Glific.parse_maybe_integer!(get_in(fields, ["contact", "id"]))

    current_week = get_current_week(organization_id, contact_id)

    %{
      batch_current_week: current_week
    }
  end

  def webhook("weekly_task", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    {_current_week, next_week} = update_week_number(organization_id)
    load_participant_file(organization_id, next_week)

    %{
      success: true
    }
  end

  def webhook("send_participant_responses", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])

    organization_id
    |> get_current_week
    |> Glific.parse_maybe_integer!()
    |> then(&upload_participant_responses(organization_id, &1))
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
      question_label: "Q#{current_week}_#{current_week_day}_#{question_id}",
      message_label: "dynamic_message_#{current_week}_#{current_week_day}"
    }
  end

  def webhook(_, fields), do: fields

  @doc """
  Hourly task jobs for the ArogyaWorld
  """
  @spec hourly_tasks(non_neg_integer()) :: any()
  def hourly_tasks(org_id) do
    Logger.info("Ran hourly tasks for organization #{org_id}")

    sharing_file_time = Timex.now().hour === 13
    current_week = get_current_week(org_id)

    get_week_day_number()
    |> do_hourly_tasks(sharing_file_time, org_id, current_week)
  end

  @spec do_hourly_tasks(non_neg_integer(), boolean(), non_neg_integer(), non_neg_integer()) ::
          any()
  defp do_hourly_tasks(1, sharing_file_time, org_id, current_week),
    do: if(sharing_file_time, do: upload_participant_responses(org_id, current_week))

  defp do_hourly_tasks(2, sharing_file_time, org_id, current_week),
    do: if(sharing_file_time, do: load_participant_file(org_id, current_week))

  defp do_hourly_tasks(7, sharing_file_time, org_id, _current_week),
    do: if(sharing_file_time, do: update_week_number(org_id))

  defp get_current_week(organization_id) do
    ## For pilot phase, it will be the day number.
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{organization_id: organization_id, key: "current_week"})

    organization_data.text
  end

  @spec get_current_week(non_neg_integer(), non_neg_integer()) :: String.t()
  defp get_current_week(organization_id, contact_id) do
    current_week = get_current_week(organization_id)
    {:ok, contact} = Repo.fetch_by(Contact, %{id: contact_id, organization_id: organization_id})

    # get the batch from contact fields and subtract from current week
    batch_number = get_in(contact.fields, ["batch", "value"])

    case batch_number do
      nil ->
        current_week

      _ ->
        (Glific.parse_maybe_integer!(current_week) - Glific.parse_maybe_integer!(batch_number) + 1)
        |> to_string()
    end
  end

  defp get_week_day_number do
    # week starts from wednesday
    rem(Timex.weekday(Timex.today()) + 4, 7) + 1
  end

  defp get_dynamic_week_key(current_week),
    do: "dynamic_message_schedule_week_#{current_week}"

  @spec get_message_id(non_neg_integer(), String.t(), non_neg_integer()) :: String.t()
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

  @doc """
  load participant files from gcs
  """
  @spec load_participant_file(non_neg_integer(), non_neg_integer()) :: any()
  def load_participant_file(org_id, week_number) do
    key = get_dynamic_week_key(week_number)
    url = "#{@csv_url_key_map["dynamic_message_schedule_week"]}#{week_number}.csv"
    add_weekly_dynamic_data(key, url, org_id)
  end

  @doc """
  get template form EEx based on variables
  """
  @spec template(integer(), String.t()) :: binary
  def template(template_uuid, variables) do
    %{
      uuid: template_uuid,
      name: "Template",
      variables: variables,
      expression: nil
    }
    |> Jason.encode!()
  end

  @doc """
  get template form EEx without variables
  """
  @spec template(integer()) :: binary
  def template(template_uuid) do
    %{
      uuid: template_uuid,
      name: "Template",
      expression: nil
    }
    |> Jason.encode!()
  end

  @doc """
  adds the weekly dynamic data loaded from the sheet based on current week
  """
  @spec add_weekly_dynamic_data(String.t(), String.t(), non_neg_integer()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def add_weekly_dynamic_data(key, file_url, org_id) do
    add_data_from_csv(
      key,
      file_url,
      &cleanup_week_data/2,
      org_id
    )
  end

  @doc """
  creates the static data map that needs to be sent to users
  """
  @spec static_message_schedule_map(String.t(), non_neg_integer()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def static_message_schedule_map(file_url, org_id) do
    add_data_from_csv(
      "static_message_schedule",
      file_url,
      &cleanup_static_data/2,
      org_id
    )
  end

  @doc """
  add data that needs to be sent to the database
  """
  @spec add_data_from_csv(String.t(), String.t(), any(), non_neg_integer()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def add_data_from_csv(key, file_url, cleanup_func, org_id) do
    # how to validate if the data is in correct format
    ApiClient.get_csv_content(url: file_url)
    |> Enum.reduce(%{}, fn {_, data}, acc ->
      cleanup_func.(acc, data)
    end)
    |> then(fn data -> Partners.maybe_insert_organization_data(key, data, org_id) end)
  end

  @doc """
  message mapping to HSM UUID
  """
  @spec message_hsm_mapping(String.t(), non_neg_integer()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def message_hsm_mapping(file_url, org_id) do
    add_data_from_csv(
      "message_template_map",
      file_url,
      fn acc, data ->
        Map.put(acc, data["Message ID"], data["Glific Template UUID"])
      end,
      org_id
    )
  end

  @doc """
  question mapping to HSM UUID
  """
  @spec question_hsm_mapping(String.t(), non_neg_integer()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def question_hsm_mapping(file_url, org_id) do
    add_data_from_csv(
      "question_template_map",
      file_url,
      fn acc, data ->
        Map.put(acc, data["Question ID"], data["Glific Template UUID"])
      end,
      org_id
    )
  end

  @doc """
  response to score mapping
  """
  @spec response_score_mapping(String.t(), non_neg_integer()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def response_score_mapping(file_url, org_id) do
    add_data_from_csv(
      "response_score_map",
      file_url,
      fn acc, data ->
        Map.put(acc, clean_string(data["1"]), 1)
        |> Map.put(clean_string(data["2"]), 2)
        |> Map.put(clean_string(data["3"]), 3)
      end,
      org_id
    )
  end

  @doc """
  Clean week data from the CSV file.
  """
  @spec cleanup_week_data(map(), map()) :: map()
  def cleanup_week_data(acc, data) do
    attr = %{
      @first_question_day => %{
        "q_id" => data["Q1_ID"],
        "m_id" => data["M1_ID"]
      },
      @second_question_day => %{
        "q_id" => data["Q2_ID"],
        "m_id" => data["M2_ID"]
      }
    }

    Map.put(acc, data["PARTICIPANT_ID"], attr)
  end

  @doc """
  Clean static weekly data from the CSV file.
  """
  @spec cleanup_static_data(map(), map()) :: map()
  def cleanup_static_data(acc, data) do
    # check for 2nd day and update it to 4th
    check_day = do_cleanup_static_data(data["Message No"], data)

    week =
      if Map.has_key?(acc, data["Week"]),
        do: Map.put(acc[data["Week"]], check_day, data["Message ID"]),
        else: %{check_day => data["Message ID"]}

    Map.put(acc, data["Week"], week)
  end

  @spec do_cleanup_static_data(String.t(), map()) :: String.t()
  defp do_cleanup_static_data("1", data),
    do: if(data["Week"] !== "1", do: @first_question_day, else: data["Message No"])

  defp do_cleanup_static_data("2", data),
    do: if(data["Week"] !== "1", do: @second_question_day, else: data["Message No"])

  defp do_cleanup_static_data(_message_no, data), do: data["Message No"]

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
  @spec get_messages_by_flow_label(String.t()) :: any()
  def get_messages_by_flow_label(label) do
    # get only last weeks data because we have same labels for pilot
    week_before = DateTime.utc_now() |> Timex.shift(days: -8)

    Message
    |> join(:inner, [m], mc in Message, on: m.id == mc.context_message_id)
    |> where([m], like(m.flow_label, ^"#{label}%") and m.inserted_at > ^week_before)
    |> select([m, mc], %{body: mc.body, contact_id: mc.contact_id, flow_label: m.flow_label})
    |> Repo.all()
  end

  @doc """
  Get response message based on day and week
  """
  @spec get_responses_by_week_and_day(non_neg_integer(), non_neg_integer(), String.t()) :: any()
  def get_responses_by_week_and_day(org_id, week, day) do
    response_label_format = "Q#{week}_#{day}_"

    get_messages_by_flow_label(response_label_format)
    |> Enum.map(fn m ->
      response_label =
        String.split(m.flow_label, ",")
        |> Enum.find(fn s -> String.starts_with?(s, response_label_format) end)

      q_id = get_question_id(response_label)

      %{
        "ID" => m.contact_id,
        "Q_ID" => q_id,
        "Q_response" => get_response_score(m.body, org_id)
      }
    end)
  end

  @doc """
  Create a file in GCS bucket for candidate response
  """
  @spec upload_participant_responses(non_neg_integer(), non_neg_integer()) :: any()
  def upload_participant_responses(org_id, week) do
    key = get_dynamic_week_key(week)

    # Question 1 responses for current week
    q1_responses = get_responses_by_week_and_day(org_id, week, @first_question_day)

    # Question 2 responses for current week
    q2_responses = get_responses_by_week_and_day(org_id, week, @second_question_day)

    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: org_id,
        key: key
      })

    dynamic_message_schedule = organization_data.json

    current_week_responses =
      Enum.map(dynamic_message_schedule, fn {id, values} ->
        %{
          "ID" => id,
          "Q1_ID" => values[@first_question_day]["q_id"],
          "Q1_response" => get_response(q1_responses, id),
          "Q2_ID" => values[@second_question_day]["q_id"],
          "Q2_response" => get_response(q2_responses, id)
        }
      end)

    # Creating a CSV file
    temp_path =
      System.tmp_dir!()
      |> Path.join("participant_response.csv")

    file = temp_path |> File.open!([:write, :utf8])

    current_week_responses
    |> CSV.encode(headers: @response_sheet_headers)
    |> Enum.each(&IO.write(file, &1))

    # Upload the file to GCS
    GcsWorker.upload_media(temp_path, "participant_responses_week_#{week}.csv", org_id)
    |> case do
      {:ok, gcs_url} -> %{url: gcs_url, error: nil}
      {:error, error} -> %{url: nil, error: error}
    end
  end

  @doc """
  Return the response of the question for a contact
  """
  @spec get_response(list(), String.t()) :: String.t() | nil
  def get_response(list, contact_id) do
    contact =
      list
      |> Enum.find(nil, fn contact ->
        Integer.to_string(contact["ID"]) === contact_id
      end)

    contact["Q_response"]
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
  @spec get_response_score(String.t(), non_neg_integer()) :: any()
  def get_response_score(response, org_id) do
    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: org_id,
        key: "response_score_map"
      })

    response = clean_string(response)

    response_score = organization_data.json

    if response_score[response] !== nil do
      response_score[response]
    else
      0
    end
  end

  @spec clean_string(String.t()) :: String.t()
  defp clean_string(str) do
    String.replace(str, " ", "")
  end
end
