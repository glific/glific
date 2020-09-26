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
  @spec request(non_neg_integer, atom, String.t(), String.t() | map) :: tuple
  def request(organization_id, method, path, body) do
    %{host: host, id: id, email: email} = project_info(organization_id)

    url = "#{host}/v2beta1/projects/#{id}/locations/global/agent/#{path}"

    case do_request(method, url, body(body), headers(email)) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Poison.decode!(body)}

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, Poison.decode!(body)}

      {:ok, %Tesla.Env{status: status, body: body}} when status >= 500 ->
        {:error, Poison.decode!(body)}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp do_request(:post, url, body, header), do: Tesla.post(url, body, headers: header)
  defp do_request(_, url, _, _), do: Tesla.get(url)

  # ---------------------------------------------------------------------------
  # Encode body
  # ---------------------------------------------------------------------------
  @spec body(String.t() | map) :: String.t()
  defp body(""), do: ""
  defp body(body), do: Poison.encode!(body)

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
  @spec project_info(non_neg_integer) :: %{
          :host => String.t(),
          :id => String.t(),
          :email => String.t()
        }
  defp project_info(organization_id) do
    case Glific.Partners.get_credential(%{
           organization_id: organization_id,
           shortcode: "dialogflow"
         }) do
      {:ok, credential} ->
        %{
          host: credential.keys["host"],
          id: credential.secrets["project_id"],
          email: credential.secrets["project_email"]
        }

      {:error, _} ->
        %{
          host: nil,
          id: nil,
          email: nil
        }
    end
  end
end
