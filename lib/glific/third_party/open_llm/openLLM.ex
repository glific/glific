defmodule Glific.OpenLLM do
  @moduledoc """
  Glific OpenLLM module for all API calls to OpenLLM
  """

  alias Glific.Partners

  use Tesla

  @doc """
  Making API call to OpenLLM  and adding Authorization token in header
  """
  @spec open_llm_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def open_llm_post(url, payload, api_key) do
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
  API call to OpenLLM
  """
  @spec parse(String.t(), String.t(), map()) :: tuple()
  def parse(api_key, url, params) do
    data = set_params(params)
    chat_url = url <> "/api/chat"

    open_llm_post(chat_url, data, api_key)
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

    organization.services["open_llm"]
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
      open_llm_post(url, %{system_prompt: system_prompt}, api_key)
    end
  end

  @doc """
    Set examples text for Open LLM with existing configurations.
    Glific.OpenLLM.set_examples_text(1, arc)
  """
  @spec set_examples_text(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def set_examples_text(org_id, examples_text) do
    with {:ok, %{api_key: api_key, api_url: api_url}} <- get_credentials(org_id) do
      url = api_url <> "/api/examples_text"
      open_llm_post(url, %{examples_text: examples_text}, api_key)
    end
  end
end
