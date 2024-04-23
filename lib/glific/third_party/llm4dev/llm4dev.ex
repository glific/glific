defmodule Glific.LLM4Dev do
  @moduledoc """
  Glific LLM4Dev module for all API calls to LLM4Dev
  """

  alias Glific.Partners

  use Tesla

  @doc """
  Making API call to LLM4Dev and adding Authorization token in header
  """
  @spec llm4dev_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def llm4dev_post(url, payload, api_key) do
    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> post(
      url,
      payload,
      opts: [adapter: [recv_timeout: 120_000]]
    )
  end

  @doc """
  API call to LLM4Dev
  """
  @spec parse(String.t(), String.t(), map()) :: tuple()
  def parse(api_key, url, params) do
    data = set_params(params)
    chat_url = url <> "/api/chat"

    llm4dev_post(chat_url, data, api_key)
    |> handle_response()
  end

  @spec set_params(map()) :: map()
  defp set_params(%{prompt: prompt, session_id: session_id}) when is_nil(session_id),
    do: %{"prompt" => prompt}

  defp set_params(%{prompt: prompt, session_id: session_id}),
    do: %{"prompt" => prompt, "session_id" => session_id}

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 201, body: body}} ->
        body
        |> Map.put(:success, true)
        |> then(&{:ok, &1})

      {_status, response} ->
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  @doc """
    Get the credentials for Open LLM with existing configurations.
  """
  @spec get_credentials(non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  def get_credentials(org_id) do
    organization = Partners.organization(org_id)

    organization.services["llm4dev"]
    |> case do
      nil ->
        {:error, "Secret not found."}

      credentials ->
        {:ok, %{api_key: credentials.secrets["api_key"], api_url: credentials.secrets["api_url"]}}
    end
  end

  @doc """
    Set system prompt for Open LLM with existing configurations.
  """
  @spec set_system_prompt(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def set_system_prompt(org_id, system_prompt) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/system_prompt"
      llm4dev_post(url, %{system_prompt: system_prompt}, api_key)
    end
  end

  @doc """
    Set examples text for Open LLM with existing configurations.
    example_text = "Question: What is Glific? \n Chatbot Answer: Glific is a no-code Whatsapp Chatbot building platform"
    set_examples_text(1, examples_text)
  """
  @spec set_examples_text(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def set_examples_text(org_id, examples_text) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/examples_text"
      llm4dev_post(url, %{examples_text: examples_text}, api_key)
    end
  end
end
