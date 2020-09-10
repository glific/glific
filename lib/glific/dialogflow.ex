defmodule Glific.Dialogflow do
  @moduledoc """
  Module to communicate with DialogFlow v2. This module was taken directly from:
  https://github.com/resuelve/flowex/

  I pulled it into our repository since the comments were in Spanish and it did not
  seem to be maintained, that we could not use as is. The dependency list was quite old etc.
  """

  alias Goth.Token

  @doc """
  The request controller which sends and parses requests. We should move this to Tesla
  """
  @spec request(atom, String.t(), String.t() | map, map()) :: tuple
  def request(method, path, body, message \\ %{}) do
    IO.inspect(%{method: method, path: path, body: body  })
    %{id: id, email: email} = project_info()

    url = "#{host()}/v2beta1/projects/#{id}/locations/global/agent/#{path}"

    case do_request(method, url, body(body), headers(email)) do
      {:ok, %Tesla.Env{status: status, body: body}}
        when status in 200..299 -> handle_success_response(Poison.decode!(body), message)

      {:ok, %Tesla.Env{status: status, body: body}}
        when status in 400..499 -> handle_error_response(body, message)

      {:ok, %Tesla.Env{status: status, body: body}}
        when status >= 500 -> handle_error_response(body, message)

      {:error, %Tesla.Error{reason: reason}} ->
        handle_error_response(reason, message)
    end
  end

  # ---------------------------------------------------------------------------
  # Encode body
  # ---------------------------------------------------------------------------
  defp do_request(:post, url, body, header), do: Tesla.post(url, body, headers: header)
  defp do_request("post", url, body, header), do: Tesla.post(url, body, headers: header)
  defp do_request(_, url, _, _), do: Tesla.get(url)


  defp handle_success_response(response, message) do
    IO.inspect("handle_success_response")
    IO.inspect(response)
    Glific.Processor.Helper.add_dialogflow_tag(Glific.atomize_keys(message), response["queryResult"])
    {:ok, response}
  end

  defp handle_error_response(error, _), do:
    {:error, error}

  @spec body(String.t() | map) :: String.t()
  defp body(""), do: ""
  defp body(body), do: Poison.encode!(body)

  # ---------------------------------------------------------------------------
  # Get the host of the dialogflow API
  # ---------------------------------------------------------------------------
  @spec host :: String.t()
  defp host, do: Application.fetch_env!(:glific, :dialogflow_url)

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
  @spec project_info() :: %{:id => String.t(), :email => String.t()}
  defp project_info do
    %{
      id: Application.fetch_env!(:glific, :dialogflow_project_id),
      email: Application.fetch_env!(:glific, :dialogflow_project_email)
    }
  end
end
