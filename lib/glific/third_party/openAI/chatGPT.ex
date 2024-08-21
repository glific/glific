defmodule Glific.OpenAI.ChatGPT do
  @moduledoc """
  Glific chatGPT module for all API calls to chatGPT
  """

  alias Glific.Partners
  require Logger

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
        "temperature" => params["temperature"]
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
        ]
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
        {:ok, hd(choices)["message"]["content"]}

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
        {:error, "invalid response #{inspect(response)}"}
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
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
  API call to fetch thread and validate thread ID
  """
  @spec fetch_thread(map()) :: map()
  def fetch_thread(%{thread_id: nil}),
    do: %{success: false, error: "invalid thread ID"}

  def fetch_thread(%{thread_id: thread_id}) do
    url = @endpoint <> "/threads/#{thread_id}"

    Tesla.get(url, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: _body}} ->
        %{success: true}

      {:ok, %Tesla.Env{status: 404, body: body}} ->
        error = Jason.decode!(body)
        %{success: false, error: error["error"]["message"]}

      {_status, _response} ->
        %{success: false, error: "invalid response returned from OpenAI"}
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
        {:error, "invalid response #{inspect(response)}"}
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
        %{"error" => "invalid response #{inspect(response)}"}
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
  @spec run_thread(map()) :: map() | {:error, String.t()}
  def run_thread(params) do
    url = @endpoint <> "/threads/#{params.thread_id}/runs"

    payload = Jason.encode!(%{"assistant_id" => params.assistant_id})

    Tesla.post(url, payload, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        run = Jason.decode!(body)
        # Waiting for atleast 10 seconds after running the thread to generate the response
        Process.sleep(10_000)
        retrieve_run_and_wait(run["thread_id"], run["id"], 10)

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
  API call to retrieve a run and check status
  """
  @spec retrieve_run_and_wait(String.t(), String.t(), non_neg_integer()) :: map()
  def retrieve_run_and_wait(thread_id, run_id, max_attempts \\ 10),
    do: retrieve_run_and_wait(thread_id, run_id, max_attempts, 0)

  @spec retrieve_run_and_wait(String.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          map()
  defp retrieve_run_and_wait(_thread_id, run_id, max_attempts, attempt)
       when attempt >= max_attempts do
    Logger.info("OpenAI run timed out after #{attempt} attempts")
    run_id
  end

  defp retrieve_run_and_wait(thread_id, run_id, max_attempts, attempt) do
    run_data =
      retrieve_run(%{
        thread_id: thread_id,
        run_id: run_id
      })

    if run_data["status"] == "completed" do
      Logger.info("OpenAI run completed after #{attempt} attempts")
      run_id
    else
      Process.sleep(3_000)
      retrieve_run_and_wait(thread_id, run_id, max_attempts, attempt + 1)
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
        {:error, "invalid response #{inspect(response)}"}
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
  API call to run a thread
  """
  @spec validate_and_get_thread_id(map()) :: map()
  def validate_and_get_thread_id(params) do
    case fetch_thread(params) do
      %{success: true} ->
        params.thread_id

      _ ->
        thread = create_thread()
        if is_map(thread), do: Map.get(thread, "id", ""), else: ""
    end
  end

  @doc """
  Handling filesearch openai conversation, basically checks if a thread id is passed then continue appending followup questions else create a new thread, add message and run thread to generate response
  """
  @spec handle_conversation(map()) :: map()
  def handle_conversation(%{thread_id: nil, remove_citation: remove_citation} = params) do
    run_thread = create_and_run_thread(params)
    Process.sleep(4_000)

    retrieve_run_and_wait(run_thread["thread_id"], run_thread["id"], 10)

    list_thread_messages(%{thread_id: run_thread["thread_id"]})
    |> remove_citation(remove_citation)
    |> Map.put_new("success", false)
  end

  def handle_conversation(%{remove_citation: remove_citation} = params) do
    thread_id = validate_and_get_thread_id(params)
    Process.sleep(4_000)

    add_message_to_thread(%{thread_id: thread_id, question: params.question})

    Process.sleep(12_000)

    run_thread(%{thread_id: thread_id, assistant_id: params.assistant_id})

    list_thread_messages(%{thread_id: thread_id})
    |> remove_citation(remove_citation)
    |> Map.put_new("success", false)
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
end
