defmodule Glific.OpenAI.ChatGPT do
  @moduledoc """
  Glific chatGPT module for all API calls to chatGPT
  """

  alias Glific.Partners
  require Logger

  alias Glific.GCS.GcsWorker

  @endpoint "https://api.openai.com/v1"

  @default_params %{
    "model" => "gpt-4o",
    "temperature" => 0.7,
    "max_tokens" => 250,
    "top_p" => 1,
    "frequency_penalty" => 0,
    "presence_penalty" => 0
  }

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
        "model" => params["model"],
        "temperature" => params["temperature"],
        "response_format" => params["response_format"]
      })

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

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
    model = Map.get(params, "model", "gpt-4-turbo")

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

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

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
        {:error, "Got empty response #{inspect(body)}"}

      {:ok, %Tesla.Env{status: 200, body: %{"choices" => choices} = _body}} ->
        case hd(choices)["message"]["content"] do
          nil -> {:error, hd(choices)["message"]["refusal"]}
          msg -> {:ok, msg}
        end

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:error, "Got different response #{inspect(body)}"}

      {_status, %Tesla.Env{status: status, body: error}} when status in 400..499 ->
        error_message = get_in(error, ["error", "message"])
        {:error, error_message}

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
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

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> Tesla.post(url, data, opts: [adapter: [recv_timeout: 120_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        uuid = Ecto.UUID.generate()
        path = write_audio_file_locally(body, uuid)

        remote_name = "Bhasini/outbound/#{uuid}.mp3"

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
  API call to create new thread
  """
  @spec create_thread() :: map() | {:error, String.t()}
  def create_thread do
    url = @endpoint <> "threads"

    Tesla.post(url, "", headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)

      {_status, response} ->
        {:error, "invalid response while creating thread #{inspect(response)}"}
    end
  end

  @doc """
  API call to create thread with message and run once
  """
  @spec create_and_run_thread(map()) :: map() | {:error, String.t()}
  def create_and_run_thread(params) do
    url = @endpoint <> "/threads/runs"

    payload =
      %{
        assistant_id: params.assistant_id,
        thread: %{
          messages: [
            %{role: "user", content: params.question}
          ]
        }
      }
      |> Jason.encode!()

    Tesla.post(url, payload, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)

      {_status, response} ->
        {:error, "invalid response while creating and running thread #{inspect(response)}"}
    end
  end

  @doc """
  Validating thread ID passed
  If nil is passed then returning {:ok, nil} as it will create new thread
  """
  @spec validate_thread_id(nil | String.t()) :: {:ok, any()} | {:error, String.t()}
  def validate_thread_id(nil), do: {:ok, nil}
  def validate_thread_id(thread_id), do: fetch_thread(%{thread_id: thread_id})

  @doc """
  API call to fetch thread and validate thread ID
  """
  @spec fetch_thread(map()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_thread(%{thread_id: nil}), do: {:error, "No thread found with nil id."}

  def fetch_thread(%{thread_id: thread_id}) do
    url = @endpoint <> "/threads/#{thread_id}"

    Tesla.get(url, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: _body}} ->
        {:ok, thread_id}

      {:ok, %Tesla.Env{status: 404, body: body}} ->
        error = Jason.decode!(body)
        {:error, error["error"]["message"]}

      {_status, _response} ->
        {:error, "invalid response while fetching thread returned from OpenAI"}
    end
  end

  @doc """
  API call to add message to a thread
  """
  @spec add_message_to_thread(map()) :: tuple()
  def add_message_to_thread(params) do
    url = @endpoint <> "/threads/#{params.thread_id}/messages"

    payload =
      %{
        "role" => "user",
        "content" => params.question
      }
      |> Jason.encode!()

    Tesla.post(url, payload, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)

      {_status, response} ->
        {:error, "invalid response while adding message to the thread #{inspect(response)}"}
    end
  end

  @doc """
  API call to list messages of a thread
  """
  @spec list_thread_messages(map()) :: map()
  def list_thread_messages(params) do
    url = @endpoint <> "/threads/#{params.thread_id}/messages"

    Tesla.get(url, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> get_last_msg()

      {_status, response} ->
        %{"error" => "invalid response while listing thread messages #{inspect(response)}"}
    end
  end

  @spec get_last_msg(map() | tuple()) :: map()
  defp get_last_msg({:error, error}) do
    Logger.error(error)
    %{"message" => "Invalid response received"}
  end

  defp get_last_msg(%{"data" => messages}) do
    [last_msg | _messages] = messages
    content = get_in(last_msg, ["content", Access.at(0)])

    %{
      "assistant_id" => last_msg["assistant_id"],
      "message" => get_in(content, ["text", "value"]),
      "thread_id" => last_msg["thread_id"],
      "success" => true
    }
  end

  @doc """
  API call to run a thread
  """
  @spec run_thread(map()) :: {:ok, String.t()} | {:error, String.t()}
  def run_thread(params) do
    re_run = Map.get(params, :re_run, false)
    url = @endpoint <> "/threads/#{params.thread_id}/runs"

    payload = Jason.encode!(%{"assistant_id" => params.assistant_id})

    Tesla.post(url, payload, headers: headers(), opts: [adapter: [recv_timeout: 20_000]])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        run = Jason.decode!(body)
        # Waiting for atleast 10 seconds after running the thread to generate the response
        Process.sleep(10_000)
        retrieve_run_and_wait(run["thread_id"], params.assistant_id, run["id"], re_run)

      {_status, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        error = Jason.decode!(body)
        error_message = get_in(error, ["error", "message"])
        {:error, error_message}

      {_status, response} ->
        {:error, "invalid response while running thread #{inspect(response)}"}
    end
  end

  @max_attempts 10
  @doc """
  API call to retrieve a run and check status
  """
  @spec retrieve_run_and_wait(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, String.t()} | {:error, String.t()}
  def retrieve_run_and_wait(thread_id, assistant_id, run_id, re_run),
    do: retrieve_run_and_wait(thread_id, assistant_id, run_id, 0, re_run)

  @spec retrieve_run_and_wait(
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          boolean()
        ) ::
          {:ok, String.t()} | {:error, String.t()}
  defp retrieve_run_and_wait(thread_id, assistant_id, run_id, attempt, false)
       when attempt >= @max_attempts do
    Logger.info(
      "OpenAI run timed out after #{attempt} attempts in first run for thread: #{thread_id}"
    )

    cancel_run(thread_id, run_id)
    Process.sleep(3_000)
    run_thread(%{thread_id: thread_id, re_run: true, assistant_id: assistant_id})
  end

  defp retrieve_run_and_wait(thread_id, _assistant_id, _run_id, attempt, true)
       when attempt >= @max_attempts do
    Logger.info(
      "OpenAI run timed out after #{attempt} attempts in second run for thread: #{thread_id}"
    )

    {:error, "OpenAI timed out"}
  end

  defp retrieve_run_and_wait(thread_id, assistant_id, run_id, attempt, re_run) do
    run =
      retrieve_run(%{
        thread_id: thread_id,
        run_id: run_id
      })

    run_attempt = if re_run, do: "second", else: "first"

    cond do
      run["status"] == "completed" ->
        Logger.info(
          "OpenAI run completed after #{attempt} attempts in #{run_attempt} run for thread: #{thread_id}"
        )

        {:ok, run_id}

      run["status"] == "in_progress" ->
        Process.sleep(5_000)
        retrieve_run_and_wait(thread_id, assistant_id, run_id, attempt + 1, re_run)

      run["status"] == "failed" ->
        {:error, "Token limit reached for this thread"}
    end
  end

  @doc """
  API call to cancel a thread
  """
  @spec cancel_run(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def cancel_run(thread_id, run_id) do
    url = @endpoint <> "/threads/#{thread_id}/runs/#{run_id}/cancel"

    Tesla.post(url, "", headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, "run cancelled"}

      {_status, response} ->
        {:error, "invalid response while cancelling thread #{inspect(response)}"}
    end
  end

  @doc """
  API call to retrieve a run
  """
  @spec retrieve_run(map()) :: map() | {:error, String.t()}
  def retrieve_run(params) do
    url = @endpoint <> "/threads/#{params.thread_id}/runs/#{params.run_id}"

    Tesla.get(url, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)

      {_status, response} ->
        {:error, "invalid response while retrieving run #{inspect(response)}"}
    end
  end

  @spec headers() :: list()
  defp headers do
    open_ai_key = Glific.get_open_ai_key()

    [
      {"Authorization", "Bearer #{open_ai_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "assistants=v2"}
    ]
  end

  @doc """
  Handling filesearch openai conversation, basically checks if a thread id is passed then continue appending followup questions else create a new thread, add message and run thread to generate response
  """
  @spec handle_conversation(map()) :: map()
  def handle_conversation(%{thread_id: nil, remove_citation: remove_citation} = params) do
    run_thread = create_and_run_thread(params)
    Process.sleep(4_000)

    case retrieve_run_and_wait(
           run_thread["thread_id"],
           params.assistant_id,
           run_thread["id"],
           false
         ) do
      {:ok, _run_id} ->
        list_thread_messages(%{thread_id: run_thread["thread_id"]})
        |> remove_citation(remove_citation)
        |> Map.put_new("success", false)

      {:error, error} ->
        error
    end
  end

  def handle_conversation(%{thread_id: thread_id, remove_citation: remove_citation} = params) do
    add_message_to_thread(%{thread_id: thread_id, question: params.question})
    Process.sleep(12_000)

    case run_thread(%{thread_id: thread_id, assistant_id: params.assistant_id}) do
      {:ok, _run_id} ->
        list_thread_messages(%{thread_id: thread_id})
        |> remove_citation(remove_citation)
        |> Map.put_new("success", false)

      {:error, error} ->
        error
    end
  end

  @doc """
  update messages based on citation flag
  """
  @spec remove_citation(map(), boolean()) :: map()
  def remove_citation(thread_messages, false), do: thread_messages

  def remove_citation(thread_messages, _true) do
    cleaned_message = Regex.replace(~r/【\d+(:\d+)?+†source】/, thread_messages["message"], "")
    Map.put(thread_messages, "message", cleaned_message)
  end

  @doc """
  API call to retrieve an assistant
  """
  @spec retrieve_assistant(map()) :: {:ok, String.t()} | {:error, String.t()}
  def retrieve_assistant(assistant_id) do
    url = @endpoint <> "/assistants/#{assistant_id}"

    Tesla.get(url, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        response = Jason.decode!(body)
        {:ok, response["name"]}

      {_status, response} ->
        error_response = Jason.decode!(response.body)

        {:error, error_response["error"]["message"]}
    end
  end
end
