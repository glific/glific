defmodule Glific.OpenAI.ChatGPT do
  @moduledoc """
  Glific chatGPT module for all API calls to chatGPT
  """

  alias Glific.Partners

  @endpoint "https://api.openai.com/v1/chat/completions"

  @default_params %{
    "model" => "gpt-3.5-turbo-16k",
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
    |> Tesla.post(@endpoint, data, opts: [adapter: [recv_timeout: 120_000]])
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
    |> Tesla.post(@endpoint, data, opts: [adapter: [recv_timeout: 120_000]])
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
  @spec create_thread() :: tuple()
  def create_thread do
    url = "https://api.openai.com/v1/threads"

    Tesla.post(url, "", headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
  API call to create new thread
  """
  @spec fetch_thread(map()) :: map()
  def fetch_thread(%{thread_id: nil}),
    do: %{success: false, error: "invalid thread ID"}

  def fetch_thread(%{thread_id: thread_id}) do
    url = "https://api.openai.com/v1/threads/#{thread_id}"

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
    url = "https://api.openai.com/v1/threads/#{params.thread_id}/messages"

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
  @spec list_thread_messages(map()) :: map() | {:error, String.t()}
  def list_thread_messages(params) do
    url = "https://api.openai.com/v1/threads/#{params.thread_id}/messages"

    Tesla.get(url, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> get_last_msg()

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @spec get_last_msg(map()) :: map()
  defp get_last_msg(%{"data" => messages}) do
    [last_msg | _messages] = messages
    content = get_in(last_msg, ["content", Access.at(0)])

    %{
      "assistant_id" => last_msg["assistant_id"],
      "message" => get_in(content, ["text", "value"]),
      "thread_id" => last_msg["thread_id"]
    }
  end

  @doc """
  API call to run a thread
  """
  @spec run_thread(map()) :: map() | {:error, String.t()}
  def run_thread(params) do
    url = "https://api.openai.com/v1/threads/#{params.thread_id}/runs"

    payload = Jason.encode!(%{"assistant_id" => params.assistant_id})

    Tesla.post(url, payload, headers: headers())
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        run = Jason.decode!(body)

        retrieve_run_and_wait(run["thread_id"], run, 10)

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
  API call to retrieve a run and check status
  """
  @spec retrieve_run_and_wait(String.t(), map(), non_neg_integer()) :: map()
  def retrieve_run_and_wait(thread_id, run, max_attempts \\ 10) do
    retrieve_run_and_wait(thread_id, run, max_attempts, 0)
  end

  @spec retrieve_run_and_wait(String.t(), map(), non_neg_integer(), non_neg_integer()) :: map()
  defp retrieve_run_and_wait(_thread_id, run, max_attempts, attempt) when attempt >= max_attempts,
    do: run

  defp retrieve_run_and_wait(thread_id, run, max_attempts, attempt) do
    run_data =
      retrieve_run(%{
        thread_id: thread_id,
        run_id: run["id"]
      })

    if run_data["status"] == "completed" do
      run
    else
      Process.sleep(2_000)
      retrieve_run_and_wait(thread_id, run, max_attempts, attempt + 1)
    end
  end

  @doc """
  API call to run a thread
  """
  @spec retrieve_run(map()) :: map() | {:error, String.t()}
  def retrieve_run(params) do
    url = "https://api.openai.com/v1/threads/#{params.thread_id}/runs/#{params.run_id}"

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
  @spec validate_and_get_thread_id(String.t() | nil) :: String.t()
  def validate_and_get_thread_id(thread_id) do
    case fetch_thread(%{thread_id: thread_id}) do
      %{success: true} ->
        thread_id

      _ ->
        thread = create_thread()
        Map.get(thread, "id", "")
    end
  end
end
