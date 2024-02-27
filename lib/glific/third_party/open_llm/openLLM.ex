defmodule Glific.OpenLLM do
  @moduledoc """
  Glific OpenLLM module for all API calls to OpenLLM
  """
  alias Glific.Partners

  @doc """
  API call to GPT
  Glific.OpenLLM.parse("sk_ABC123", "What is sbic curriculum", %{})
  """
  @spec parse(String.t(), String.t()) :: tuple()
  def parse(api_key, prompt) do
    data = %{"prompt" => prompt}

    middleware = [
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", api_key}]}
    ]

    middleware
    |> Tesla.client()
    |> Tesla.post(
      "https://6f2e-2401-4900-81f1-15d2-8137-ec1-6836-ca9a.ngrok-free.app/api/chat",
      data,
      opts: [adapter: [recv_timeout: 120_000]]
    )
    |> handle_response()
  end

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 201, body: %{"answer" => answer}}} ->
        {:success, answer}

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

    organization.services["open_llm"]
    |> case do
      nil ->
        {:error, "Secret not found."}

      credentials ->
        {:ok, %{api_key: credentials.secrets["api_key"]}}
    end
  end
end
