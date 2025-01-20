defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.
  """

  alias Glific.{
    ASR.Bhasini,
    ASR.GoogleASR,
    Contacts,
    LLM4Dev,
    OpenAI.ChatGPT,
    Sheets.GoogleSheets
  }

  require Logger

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("parse_via_chat_gpt", fields) do
    with {:ok, fields} <- parse_chatgpt_fields(fields),
         {:ok, fields} <- parse_response_format(fields),
         {:ok, text} <- Glific.get_open_ai_key() |> ChatGPT.parse(fields) do
      %{
        success: true,
        parsed_msg: parse_gpt_response(text)
      }
    else
      {:error, error} ->
        %{
          success: false,
          parsed_msg: error
        }
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

  @spec webhook(String.t(), map()) :: any()
  def webhook("parse_via_gpt_vision", fields) do
    url = fields["url"]
    # validating if the url passed is a valid image url
    with %{is_valid: true} <- Glific.Messages.validate_media(url, "image"),
         {:ok, fields} <- parse_response_format(fields),
         {:ok, response} <- ChatGPT.gpt_vision(fields) do
      %{success: true, response: parse_gpt_response(response)}
    else
      %{is_valid: false, message: message} ->
        Logger.error("OpenAI GPTVision failed for URL: #{url} with error: #{message}")
        message

      {:error, error} ->
        Logger.error("OpenAI GPTVision failed for URL: #{url} with error: #{error}")
        error
    end
  end

  def webhook("filesearch-gpt", fields) do
    question = fields["question"]
    thread_id = Map.get(fields, "thread_id", nil)
    assistant_id = Map.get(fields, "assistant_id", nil)
    remove_citation = Map.get(fields, "remove_citation", false)

    with {:ok, _assistant_name} <- ChatGPT.retrieve_assistant(assistant_id),
         {:ok, thread_id} <- ChatGPT.validate_thread_id(thread_id) do
      params = %{
        thread_id: thread_id,
        assistant_id: assistant_id,
        question: question,
        remove_citation: remove_citation
      }

      ChatGPT.handle_conversation(params)
    else
      {:error, error} -> error
    end
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
    contact = Contacts.preload_contact_language(contact_id)

    Glific.parse_maybe_integer!(fields["organization_id"])
    |> GoogleASR.speech_to_text(fields["results"], contact.language.locale)
  end

  # This webhook will call Bhashini speech-to-text API
  def webhook("speech_to_text_with_bhasini", fields) do
    case Bhasini.validate_params(fields) do
      {:ok, contact} ->
        source_language = contact.language.locale
        {:ok, media_content} = Tesla.get(fields["speech"])

        content = Base.encode64(media_content.body)

        Bhasini.make_asr_api_call(
          source_language,
          content
        )

      {:error, error} ->
        error
    end
  end

  # This webhook will call Bhashini text-to-speech API
  def webhook("text_to_speech_with_bhasini", fields) do
    text = fields["text"]
    org_id = fields["organization_id"]
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = Contacts.preload_contact_language(contact_id)
    source_language = contact.language.label |> String.downcase()

    if source_language == "english" do
      ChatGPT.text_to_speech_with_open_ai(org_id, text)
    else
      Glific.Bhasini.text_to_speech_with_bhashini(source_language, org_id, text)
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

    cond do
      source_language == target_language && source_language == "english" ->
        ChatGPT.text_to_speech_with_open_ai(org_id, text)

      source_language == target_language ->
        Glific.Bhasini.text_to_speech_with_bhashini(source_language, org_id, text)

      true ->
        do_nmt_tts_with_bhasini(source_language, target_language, org_id, text)
    end
  end

  def webhook("detect_language", fields) do
    speech = fields["speech"]
    Bhasini.detect_language(speech)
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
            district = find_component(components, "administrative_area_level_3")

            %{
              success: true,
              city: city,
              state: state,
              country: country,
              postal_code: postal_code,
              district: district,
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

  @spec do_nmt_tts_with_bhasini(String.t(), String.t(), non_neg_integer(), String.t()) :: map()
  defp do_nmt_tts_with_bhasini(source_language, target_language, org_id, text) do
    organization = Glific.Partners.organization(org_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         true <- Glific.Bhasini.valid_language?(source_language, target_language) do
      Glific.Bhasini.nmt_tts(text, source_language, target_language, org_id)
    else
      true ->
        %{success: false, reason: "GCS is disabled"}

      false ->
        %{success: false, reason: "Language not supported in Bhashini"}
    end
  end

  defp parse_response_format(%{"response_format" => response_format} = fields) do
    case response_format do
      %{"type" => "json_schema"} ->
        # Support for json_schema is only since gpt-4o-2024-08-06
        {:ok, Map.put(fields, "model", "gpt-4o-2024-08-06")}

      %{"type" => "json_object"} ->
        {:ok, fields}

      nil ->
        {:ok, fields}

      _ ->
        {:error, "response_format type should be json_schema or json_object"}
    end
  end

  defp parse_response_format(fields), do: {:ok, Map.put(fields, "response_format", nil)}

  @spec parse_gpt_response(String.t()) :: any()
  defp parse_gpt_response(response) do
    case Jason.decode(response) do
      {:ok, decoded_response} ->
        decoded_response

      {:error, _err} ->
        response
    end
  end

  @spec parse_chatgpt_fields(map()) :: {:ok, map()} | {:error, String.t()}
  defp parse_chatgpt_fields(fields) do
    if fields["question_text"] in [nil, ""] do
      {:error, "question_text is empty"}
    else
      {:ok,
       %{
         "question_text" => Map.get(fields, "question_text"),
         "prompt" => Map.get(fields, "prompt", nil),
         # ID of the model to use.
         "model" => Map.get(fields, "model", "gpt-4o"),
         # The sampling temperature, between 0 and 1.
         # Higher values like 0.8 will make the output more random,
         # while lower values like 0.2 will make it more focused and deterministic.
         "temperature" => Map.get(fields, "temperature", 0),
         "response_format" => Map.get(fields, "response_format", nil)
       }}
    end
  end
end
