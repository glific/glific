defmodule Glific.Flowex do
  @moduledoc """
  Module to communicate with DialogFlow v2
  """

  alias Goth.Token

  @spec request(String.t(), atom, String.t(), String.t() | map) :: tuple
  def request(project, method, path, body) do
    %{id: id, email: email} = project_info(project)

    url = "#{host()}/v2/projects/#{id}/agent/#{path}"

    case HTTPoison.request(method, url, body(body), headers(email)) do
      {:ok, %HTTPoison.Response{status_code: status, body: body}} when status in 200..299 ->
        {:ok, Poison.decode!(body)}
      {:ok, %HTTPoison.Response{status_code: status, body: body}} when status in 400..499 ->
        IO.inspect(body)
        {:error, Poison.decode!(body)}
      {:ok, %HTTPoison.Response{status_code: status, body: body}} when status >= 500 ->
        {:error, Poison.decode!(body)}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Poison.decode!(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Encode body
  # ---------------------------------------------------------------------------
  @spec body(String.t() | map) :: String.t
  defp body(""), do: ""
  defp body(body), do: Poison.encode!(body)

  # ---------------------------------------------------------------------------
  # Obtine el host de Dialogflow API
  # ---------------------------------------------------------------------------
  @spec host :: String.t
  defp host(), do: Application.fetch_env!(:glific, :dialogflow_url)

  # ---------------------------------------------------------------------------
  # Headers for all subsequent API calls
  # ---------------------------------------------------------------------------
  @spec headers(String.t()) :: list
  defp headers(_email) do
    {:ok, token} = Token.for_scope("https://www.googleapis.com/auth/cloud-platform")

    [
      {"Authorization", "Bearer #{token.token}"},
      {"Content-Type", "application/json"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Get the project details needed for authentication and to send via the API
  # ---------------------------------------------------------------------------
  @spec project_info(String.t) :: %{:id => String.t, :email => String.t}
  defp project_info(_project) do
    %{
      id: Application.fetch_env!(:glific, :dialogflow_project_id),
      email: Application.fetch_env!(:glific, :dialogflow_project_email)
    }
  end
end
