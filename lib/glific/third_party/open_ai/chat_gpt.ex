defmodule Glific.OpenAI.ChatGPT do
  @moduledoc """
  Glific chatGPT module for all API calls to chatGPT
  """

  alias Glific.GCS.GcsWorker
  alias Glific.Partners

  @endpoint "https://api.openai.com/v1"

  @default_params %{
    "temperature" => 0.7,
    "top_p" => 1,
    "frequency_penalty" => 0,
    "presence_penalty" => 0
  }

  @spec gpt_model() :: String.t()
  defp gpt_model, do: Application.fetch_env!(:glific, __MODULE__)[:gpt_model]

  @doc """
  API call to GPT for translation with text only
  """
  @spec parse(String.t(), String.t(), map()) :: tuple()
  def parse(api_key, question_text, params) do
    data =
      @default_params
      |> Map.merge(params)
      |> Map.put("question_text", question_text)

    parse(api_key, data)
  end

  @doc """
  API call to GPT
  """
  @spec parse(String.t(), map()) :: tuple()
  def parse(api_key, params) do
    url = @endpoint <> "/chat/completions"

    data =
      @default_params
      |> Map.merge(%{
        "messages" => add_prompt(params),
        "model" => params["model"] || gpt_model(),
        "temperature" => params["temperature"],
        "response_format" => params["response_format"]
      })

    middleware =
      [
        Tesla.Middleware.JSON
      ] ++ get_tesla_middlewares(api_key)

    middleware
    |> Tesla.client()
    |> Tesla.post(url, data, opts: [adapter: [recv_timeout: 120_000]])
    |> handle_response()
  end

  @spec add_prompt(map()) :: list()
  defp add_prompt(params) do
    %{
      "role" => "user",
      "content" => params["question_text"]
    }
    |> add_system_prompt(params)
  end

  @spec add_system_prompt(map(), map()) :: list()
  defp add_system_prompt(message, %{"prompt" => nil} = _params), do: [message]

  defp add_system_prompt(message, params),
    do: [
      %{
        "role" => "system",
        "content" => params["prompt"]
      },
      message
    ]

  @doc """
  API call to GPT-4 Turbo with Vision
  """
  @spec gpt_vision(map()) :: tuple()
  def gpt_vision(params \\ %{}) do
    url = @endpoint <> "/chat/completions"
    api_key = Glific.get_open_ai_key()
    model = Map.get(params, "model", gpt_model())

    data =
      %{
        "model" => model,
        "messages" => [
          %{
            "role" => "user",
            "content" => [
              %{
                "type" => "text",
                "text" => params["prompt"]
              },
              %{
                "type" => "image_url",
                "image_url" => %{
                  "url" => params["url"],
                  "detail" => "high"
                }
              }
            ]
          }
        ],
        "response_format" => params["response_format"]
      }

    middleware = [Tesla.Middleware.JSON] ++ get_tesla_middlewares(api_key)

    middleware
    |> Tesla.client()
    |> Tesla.post(url, data, opts: [adapter: [recv_timeout: 120_000]])
    |> handle_response()
  end

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{"choices" => []} = body}} ->
        {:error, "Got empty response #{Glific.SafeLog.safe_inspect(body)}"}

      {:ok, %Tesla.Env{status: 200, body: %{"choices" => choices} = _body}} ->
        case hd(choices)["message"]["content"] do
          nil -> {:error, hd(choices)["message"]["refusal"]}
          msg -> {:ok, msg}
        end

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Got different response #{Glific.SafeLog.safe_inspect(body)}"}

      {_status, %Tesla.Env{status: status, body: error}} when status in 400..499 ->
        error_message = get_in(error, ["error", "message"])
        {:error, error_message}

      {_status, response} ->
        {:error, "Invalid response #{Glific.SafeLog.safe_inspect(response)}"}
    end
  end

  @doc """
  Normalise the OpenAI `response_format` option for a webhook request.

  `json_schema` is only supported since `gpt-4o-2024-08-06`, so pin the model when it is
  requested; `json_object` and no format pass through unchanged. Returns `{:error, reason}`
  for an unrecognised format type.
  """
  @spec parse_response_format(map()) :: {:ok, map()} | {:error, String.t()}
  def parse_response_format(%{"response_format" => response_format} = fields) do
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

  def parse_response_format(fields), do: {:ok, Map.put(fields, "response_format", nil)}

  @doc """
  Decode a GPT response body as JSON, returning the raw string when it is not valid JSON.
  """
  @spec parse_gpt_response(String.t()) :: any()
  def parse_gpt_response(response) do
    case Jason.decode(response) do
      {:ok, decoded_response} ->
        decoded_response

      {:error, _err} ->
        response
    end
  end

  @doc """
  This function makes an API call to the OpenAI and returns the public media URL of the file.
  """
  @spec text_to_speech(non_neg_integer(), String.t(), String.t(), String.t()) :: map()
  def text_to_speech(org_id, text, voice \\ "nova", model \\ "tts-1") do
    url = @endpoint <> "/audio/speech"
    api_key = Glific.get_open_ai_key()

    data = %{
      "model" => model,
      "input" => text,
      "voice" => voice
    }

    middleware = [Tesla.Middleware.JSON] ++ get_tesla_middlewares(api_key)

    middleware
    |> Tesla.client()
    |> Tesla.post(url, data, opts: [adapter: [recv_timeout: 120_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        uuid = Ecto.UUID.generate()
        path = write_audio_file_locally(body, uuid)

        remote_name = "Gemini/outbound/#{uuid}.mp3"

        {:ok, media_meta} =
          GcsWorker.upload_media(
            path,
            remote_name,
            org_id
          )

        %{media_url: media_meta.url}

      _ ->
        %{success: false, reason: "Could not generate Audio note"}
    end
  end

  # locally downloading the file before uploading it to GCS to get public URL of file to be used at flow level
  @spec write_audio_file_locally(String.t(), String.t()) :: String.t()
  defp write_audio_file_locally(encoded_audio, uuid) do
    path = System.tmp_dir!() <> "#{uuid}.mp3"
    :ok = File.write!(path, encoded_audio)
    path
  end

  @doc """
    Get the API key with existing configurations.
  """
  @spec get_api_key(non_neg_integer()) :: String.t()
  def get_api_key(org_id) do
    {:ok, %{api_key: api_key}} = credentials(org_id)
    api_key
  end

  @spec credentials(non_neg_integer()) :: tuple()
  defp credentials(org_id) do
    organization = Partners.organization(org_id)

    organization.services["open_ai"]
    |> case do
      nil ->
        {:error, "Secret not found."}

      credentials ->
        {:ok, %{api_key: credentials.secrets["api_key"]}}
    end
  end

  @doc """
  This function check if GCS credentials are valid and then proceed to convert text to speech using OpenAI
  """
  @spec text_to_speech_with_open_ai(non_neg_integer(), String.t()) ::
          map()
  def text_to_speech_with_open_ai(org_id, text) do
    organization = Glific.Partners.organization(org_id)
    services = organization.services["google_cloud_storage"]

    with false <- is_nil(services),
         %{media_url: media_url} <- text_to_speech(org_id, text) do
      %{success: true}
      |> Map.put(:media_url, media_url)
      |> Map.put(:translated_text, text)
    else
      true ->
        %{success: false, reason: "GCS is disabled"}

      error ->
        error
    end
  end

  @spec get_tesla_middlewares(String.t()) :: list()
  defp get_tesla_middlewares(api_key) do
    [{Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}] ++
      get_tesla_telemetry_middlewares()
  end

  @spec get_tesla_telemetry_middlewares :: list()
  defp get_tesla_telemetry_middlewares do
    [
      Tesla.Middleware.KeepRequest,
      Tesla.Middleware.PathParams,
      {Tesla.Middleware.Telemetry, metadata: %{provider: "openai", sampling_scale: 8}}
    ] ++ Glific.get_tesla_retry_middleware()
  end
end
