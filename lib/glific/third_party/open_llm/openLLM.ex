defmodule Glific.OpenLLM do
  @moduledoc """
  Glific OpenLLM module for all API calls to OpenLLM
  """
  alias Glific.Partners

  @doc """
  API call to OpenLLM
  """
  @spec parse(String.t(), String.t(), map()) :: tuple()
  def parse(api_key, api_url, params) do
    data = set_params(params)

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> Tesla.post(
      api_url,
      data,
      opts: [adapter: [recv_timeout: 120_000]]
    )
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
  @spec get_credentials(non_neg_integer()) :: String.t()
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
end
