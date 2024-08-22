defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.
  """

  alias Glific.{
    ASR.Bhasini,
    ASR.GoogleASR,
    Contacts.Contact,
    LLM4Dev,
    OpenAI.ChatGPT,
    Repo,
    Sheets.GoogleSheets
  }

  require Logger

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("parse_via_chat_gpt", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    question_text = fields["question_text"]
    prompt = Map.get(fields, "prompt", nil)

    # ID of the model to use.
    model = Map.get(fields, "model", "gpt-3.5-turbo")

    # The sampling temperature, between 0 and 1.
    # Higher values like 0.8 will make the output more random,
    # while lower values like 0.2 will make it more focused and deterministic.
    temperature = Map.get(fields, "temperature", 0)

    params = %{
      "question_text" => question_text,
      "prompt" => prompt,
      "model" => model,
      "temperature" => temperature
    }

    if question_text in [nil, ""] do
      %{
        success: false,
        parsed_msg: "Could not parsed"
      }
    else
      ChatGPT.get_api_key(org_id)
      |> ChatGPT.parse(params)
      |> case do
        {:ok, text} ->
          %{
            success: true,
            parsed_msg: text
          }

        {_, error} ->
          %{
            success: false,
            parsed_msg: error
          }
      end
    end
  end

  def webhook("voice-filesearch-gpt", fields) do
    with %{
           success: true,
           asr_response_text: asr_response_text
         } <- webhook("speech_to_text_with_bhasini", fields),
         %{
           "success" => true,
           "thread_id" => thread_id,
           "message" => filesearch_response
         } <- webhook("filesearch-gpt", Map.put(fields, "question", asr_response_text)) do
      webhook("nmt_tts_with_bhasini", Map.put(fields, "text", filesearch_response))
      |> Map.put("thread_id", thread_id)
    end
  end

  @spec webhook(String.t(), map()) :: map()
  def webhook("parse_via_gpt_vision", fields) do
    ChatGPT.gpt_vision(fields)
    |> case do
      {:ok, response} -> %{success: true, response: response}
      {:error, error} -> %{success: false, error: error}
    end
  end

  def webhook("filesearch-gpt", fields) do
    question = fields["question"]
    thread_id = Map.get(fields, "thread_id", nil)
    assistant_id = Map.get(fields, "assistant_id", nil)
    remove_citation = Map.get(fields, "remove_citation", false)

    params = %{
      thread_id: thread_id,
      assistant_id: assistant_id,
      question: question,
      remove_citation: remove_citation
    }

    ChatGPT.handle_conversation(params)
  end

  def webhook("llm4dev", fields) do
    org_id = Glific.parse_maybe_integer!(fields["organization_id"])
    question = fields["question"]
    session_id = Map.get(fields, "session_id", nil)
    category_id = Map.get(fields, "category_id", nil)
    system_prompt = Map.get(fields, "system_prompt", nil)

    params = %{
      question: question,
      session_id: session_id,
      category_id: category_id,
      system_prompt: system_prompt
    }

    with {:ok, %{api_key: api_key, api_url: api_url}} <- LLM4Dev.get_credentials(org_id),
         {:ok, response} <-
           LLM4Dev.parse(api_key, api_url, params) do
      response
    else
      {:error, error} ->
        %{success: false, error: error}
    end
  end

  def webhook("sheets.insert_row", fields) do
    org_id = fields["organization_id"]
    range = fields["range"] || "A:Z"
    spreadsheet_id = fields["spreadsheet_id"]
    row_data = fields["row_data"]

    with {:ok, response} <-
           GoogleSheets.insert_row(org_id, spreadsheet_id, %{range: range, data: [row_data]}) do
      %{response: "#{inspect(response)}"}
    end
  end

  def webhook("jugalbandi", fields) do
    prompt = if Map.has_key?(fields, "prompt"), do: [prompt: fields["prompt"]], else: []

    query =
      [
        query_string: fields["query_string"],
        uuid_number: fields["uuid_number"]
      ] ++ prompt

    Tesla.get(fields["url"],
      headers: [{"Accept", "application/json"}],
      query: query,
      opts: [adapter: [recv_timeout: 100_000]]
    )
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> Map.take(["answer"])
        |> Map.merge(%{success: true})

      {_status, response} ->
        %{success: false, response: "Invalid response #{response}"}
    end
  end

  def webhook("openllm", fields) do
    mp = Tesla.Multipart.add_field(Tesla.Multipart.new(), "prompt", fields["prompt"])

    Tesla.post(fields["url"], mp, opts: [adapter: [recv_timeout: 100_000]])
    |> case do
      {:ok, %Tesla.Env{status: 201, body: body}} ->
        Jason.decode!(body)
        |> Map.take(["answer", "session_id"])

      {_status, response} ->
        %{success: false, response: "Invalid response #{response}"}
    end
  end

  def webhook("jugalbandi-voice", %{"query_text" => query_text} = fields),
    do: query_jugalbandi_api(fields, query_text: query_text)

  def webhook("jugalbandi-voice", %{"audio_url" => audio_url} = fields),
    do: query_jugalbandi_api(fields, audio_url: audio_url)

  # This webhook will call Google speech-to-text API
  def webhook("speech_to_text", fields) do
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = get_contact_language(contact_id)

    Glific.parse_maybe_integer!(fields["organization_id"])
    |> GoogleASR.speech_to_text(fields["results"], contact.language.locale)
  end

  # This webhook will call Bhasini speech-to-text API
  def webhook("speech_to_text_with_bhasini", fields) do
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = get_contact_language(contact_id)

    with {:ok, response} <-
           Bhasini.with_config_request(
             source_language: contact.language.locale,
             task_type: "asr"
           ) do
      {:ok, media_content} = Tesla.get(fields["speech"])

      content = Base.encode64(media_content.body)
      Bhasini.handle_response(response, content)
    end
  end

  # This webhook will call Bhasini text-to-speech API
  def webhook("text_to_speech_with_bhasini", fields) do
    text = fields["text"]
    org_id = fields["organization_id"]
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = get_contact_language(contact_id)
    organization = Glific.Partners.organization(org_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         {:ok, response} <-
           Bhasini.with_config_request(source_language: contact.language.locale, task_type: "tts"),
         %{"feedbackUrl" => _feedback_url, "pipelineInferenceAPIEndPoint" => _endpoint} = params <-
           Jason.decode!(response.body) do
      Glific.Bhasini.text_to_speech(params, text, org_id)
    else
      true ->
        %{success: false, reason: "GCS is disabled"}

      {:error, error} ->
        Map.put(error, "success", false)

      error ->
        Logger.error("Error received from Bhasini: #{error["message"]}")
        Map.put(error, "success", false)
    end
  end

  def webhook("nmt_tts_with_bhasini", fields) do
    text = fields["text"]
    org_id = fields["organization_id"]

    source_language =
      fields
      |> Map.get("source_language", nil)
      |> then(&if(!is_nil(&1), do: String.downcase(&1)))

    target_language =
      fields
      |> Map.get("target_language", nil)
      |> then(&if(!is_nil(&1), do: String.downcase(&1)))

    organization = Glific.Partners.organization(org_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         true <- Glific.Bhasini.valid_language?(source_language, target_language),
         {:ok, response} <-
           Bhasini.with_config_request(
             source_language: source_language,
             target_language: target_language,
             task_type: "nmt_tts"
           ),
         %{"feedbackUrl" => _feedback_url, "pipelineResponseConfig" => _pipelineresponseconfig} =
           params <-
           Jason.decode!(response.body) do
      Glific.Bhasini.nmt_tts(params, text, source_language, target_language, org_id)
    else
      true ->
        %{success: false, reason: "GCS is disabled"}

      false ->
        %{success: false, reason: "Language not supported in Bhasini"}

      {:error, error} ->
        Map.put(error, "success", false)

      error ->
        Logger.error("Error received from Bhasini: #{error["message"]}")
        Map.put(error, "success", false)
    end
  end

  def webhook("get_buttons", fields) do
    buttons =
      fields["buttons_data"]
      |> String.split("|")
      |> Enum.with_index()
      |> Enum.map(fn {answer, index} -> {"button_#{index + 1}", String.trim(answer)} end)
      |> Enum.into(%{})

    %{
      buttons: buttons,
      button_count: length(Map.keys(buttons)),
      is_valid: true
    }
  end

  def webhook("check_response", fields),
    do: %{response: String.equivalent?(fields["correct_response"], fields["user_response"])}

  def webhook("geolocation", fields) do
    lat = fields["lat"]
    long = fields["long"]
    api_key = Glific.get_google_maps_api_key()

    url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=#{lat},#{long}&key=#{api_key}"

    Tesla.get(url)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        %{"results" => results} = Jason.decode!(body)

        Glific.Metrics.increment("Geolocation API Success")

        case results do
          [%{"address_components" => components, "formatted_address" => formatted_address} | _] ->
            city = find_component(components, "locality")
            state = find_component(components, "administrative_area_level_1")
            country = find_component(components, "country")
            postal_code = find_component(components, "postal_code")
            district = find_component(components, "administrative_area_level_2")
            ward = find_component(components, "administrative_area_level_3")

            %{
              success: true,
              city: city,
              state: state,
              country: country,
              postal_code: postal_code,
              district: district,
              ward: ward,
              address: formatted_address
            }

          _ ->
            %{success: false, error: "No results found"}
        end

      {:ok, %Tesla.Env{status: status_code}} ->
        Glific.Metrics.increment("Geolocation API Failure")
        %{success: false, error: "Received status code #{status_code}"}

      {:error, reason} ->
        Glific.Metrics.increment("Geolocation API Failure")
        %{success: false, error: "HTTP request failed: #{reason}"}
    end
  end

  def webhook(_, _fields), do: %{error: "Missing webhook function implementation"}

  defp get_contact_language(contact_id) do
    case Repo.fetch(Contact, contact_id) do
      {:ok, contact} -> contact |> Repo.preload(:language)
      {:error, error} -> error
    end
  end

  @spec find_component(list(map()), String.t()) :: String.t()
  defp find_component(components, type) do
    case Enum.find(components, fn component -> type in component["types"] end) do
      nil -> "N/A"
      component -> component["long_name"]
    end
  end

  @spec query_jugalbandi_api(map(), list()) :: map()
  defp query_jugalbandi_api(fields, input) do
    query =
      [
        uuid_number: fields["uuid_number"],
        input_language: fields["input_language"],
        output_format: fields["output_format"]
      ] ++ input

    Tesla.get(fields["url"],
      headers: [{"Accept", "application/json"}],
      query: query,
      opts: [adapter: [recv_timeout: 200_000]]
    )
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> Map.take(["answer", "audio_output_url"])
        |> Map.merge(%{success: true})

      {_status, response} ->
        %{success: false, response: "Invalid response #{response}"}
    end
  end
end
