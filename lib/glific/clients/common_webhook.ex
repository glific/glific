defmodule Glific.Clients.CommonWebhook do
  @moduledoc """
  Common webhooks which we can call with any clients.
  """

  alias Glific.{
    ASR.Bhasini,
    ASR.GoogleASR,
    Contacts,
    Groups.WAGroup,
    GCS.GcsWorker,
    OpenAI.ChatGPT,
    Providers.Maytapi,
    Repo,
    WAGroup.WAManagedPhone,
    WAGroup.WaPoll
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

  # This webhook will call Google speech-to-text API
  def webhook("speech_to_text", fields) do
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = Contacts.preload_contact_language(contact_id)

    Glific.parse_maybe_integer!(fields["organization_id"])
    |> GoogleASR.speech_to_text(fields["results"], contact.language.locale)
  end

  # This webhook will call Bhashini speech-to-text API
  def webhook("speech_to_text_with_bhasini", fields) do
    with {:ok, contact} <- Bhasini.validate_params(fields),
         {:ok, media_content} <- Tesla.get(fields["speech"]) do
      source_language = contact.language.locale
      content = Base.encode64(media_content.body)

      Bhasini.make_asr_api_call(
        source_language,
        content
      )
    else
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
    speech_engine = Map.get(fields, "speech_engine", "")

    cond do
      speech_engine == "open_ai" ->
        ChatGPT.text_to_speech_with_open_ai(org_id, text)

      speech_engine == "bhashini" ->
        Glific.Bhasini.text_to_speech_with_bhashini(source_language, org_id, text)

      source_language == "english" ->
        ChatGPT.text_to_speech_with_open_ai(org_id, text)

      true ->
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

    speech_engine = Map.get(fields, "speech_engine", "")

    cond do
      speech_engine == "bhashini" && source_language == target_language ->
        Glific.Bhasini.text_to_speech_with_bhashini(source_language, org_id, text)

      source_language == target_language && source_language == "english" ->
        ChatGPT.text_to_speech_with_open_ai(org_id, text)

      source_language == target_language ->
        Glific.Bhasini.text_to_speech_with_bhashini(source_language, org_id, text)

      true ->
        do_nmt_tts_with_bhasini(source_language, target_language, org_id, text,
          speech_engine: speech_engine
        )
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

  # webhook for sending whatsapp group polls in a flow
  def webhook("send_wa_group_poll", fields) do
    with {:ok, fields} <- parse_wa_poll_params(fields),
         {:ok, wa_phone} <-
           Repo.fetch_by(WAManagedPhone, %{
             id: fields.wa_group["wa_managed_phone_id"],
             organization_id: fields.organization_id
           }),
         {:ok, wa_group} <-
           Repo.fetch_by(WAGroup, %{
             id: fields.wa_group["id"],
             organization_id: fields.organization_id
           }),
         {:ok, wa_poll} <-
           Repo.fetch_by(WaPoll, %{
             uuid: fields.poll_uuid,
             organization_id: fields.organization_id
           }),
         {:ok, wa_message} <-
           Maytapi.Message.create_and_send_wa_message(wa_phone, wa_group, %{poll_id: wa_poll.id}) do
      %{success: true, poll: wa_message.poll_content}
    else
      {:error, reason} when is_binary(reason) ->
        %{success: false, error: "#{reason}"}

      {:error, reason} ->
        %{success: false, error: "#{inspect(reason)}"}
    end
  end

  def webhook("create_certificate", fields) do
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])

    with {:ok, thumbnail} <-
           Glific.ThirdParty.GoogleSlide.Slide.create_certificate(
             fields["organization_id"],
             fields["presentation_id"],
             fields["replace_texts"]
           ),
         {:ok, image} <-
           download_file(
             thumbnail,
             fields["presentation_id"],
             contact_id,
             fields["organization_id"]
           ) do
      %{success: true, certificate_url: image}
    else
      {:error, error} ->
        %{
          success: false,
          parsed_msg: error
        }
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

  @spec do_nmt_tts_with_bhasini(
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t(),
          Keyword.t()
        ) :: map()
  defp do_nmt_tts_with_bhasini(source_language, target_language, org_id, text, opts) do
    organization = Glific.Partners.organization(org_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         true <- Glific.Bhasini.valid_language?(source_language, target_language) do
      Glific.Bhasini.nmt_tts(text, source_language, target_language, org_id, opts)
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

  @spec parse_wa_poll_params(map()) :: {:ok, map()} | {:error, String.t()}
  defp parse_wa_poll_params(fields) do
    # if wa_group is in the map, then the inner keys will be already filled by
    # webhook module
    with {true, _} <- {is_map(fields["wa_group"]), :wa_group},
         {true, _} <- {is_integer(fields["organization_id"]), :organization_id},
         {:ok, _} <-
           Ecto.UUID.cast(fields["poll_uuid"]) do
      {:ok,
       %{
         wa_group: fields["wa_group"],
         poll_uuid: fields["poll_uuid"],
         organization_id: fields["organization_id"]
       }}
    else
      :error ->
        {:error, "poll_uuid is invalid"}

      {false, field} ->
        {:error, "#{field} is invalid"}
    end
  end

  @spec download_file(
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer() :: {:ok, String.t()} | {:error, String.t()}
        )
  defp download_file(thumbnail_url, presentation_id, contact_id, org_id) do
    remote_name = "certificate/#{presentation_id}/#{contact_id}.png"
    uuid = Ecto.UUID.generate()
    temp_path = Path.join(System.tmp_dir!(), "#{uuid}.png")

    with {:ok, %Tesla.Env{status: 200, body: image_data}} <- Tesla.get(thumbnail_url),
         :ok <- File.write(temp_path, image_data),
         {:ok, media_meta} <- GcsWorker.upload_media(temp_path, remote_name, org_id) do
      File.rm(temp_path)
      {:ok, media_meta.url}
    else
      {:error, reason} ->
        File.rm(temp_path)
        {:error, reason}

      {:ok, %Tesla.Env{status: status}} when status != 200 ->
        {:error, :download_failed}
    end
  end
end
