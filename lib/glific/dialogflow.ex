defmodule Glific.Dialogflow do
  @moduledoc """
  Module to communicate with DialogFlow v2. This module was taken directly from:
  https://github.com/resuelve/flowex/

  I pulled it into our repository since the comments were in Spanish and it did not
  seem to be maintained, that we could not use as is. The dependency list was quite old etc.
  """

  alias Glific.Partners
  alias Goth.Token

  @doc """
  The request controller which sends and parses requests. We should move this to Tesla
  """
  @spec request(non_neg_integer, atom, String.t(), String.t() | map) :: tuple
  def request(organization_id, method, path, body) do
    %{url: url, id: id, email: email} = project_info(organization_id)

    dflow_url = "#{url}/v2beta1/projects/#{id}/locations/global/agent/#{path}"

    do_request(method, dflow_url, body(body), headers(email, organization_id))
    |> case do
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
  @spec headers(String.t(), non_neg_integer) :: list
  defp headers(email, org_id) do
    Partners.check_and_load_goth_config(email, org_id)
    {:ok, token} = Token.for_scope({email, "https://www.googleapis.com/auth/cloud-platform"})

    [
      {"Authorization", "Bearer #{token.token}"},
      {"Content-Type", "application/json"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Get the project details needed for authentication and to send via the API
  # ---------------------------------------------------------------------------
  @spec project_info(non_neg_integer) :: %{
          :url => String.t(),
          :id => String.t(),
          :email => String.t()
        }
  defp project_info(organization_id) do
    case Partners.get_credential(%{
           organization_id: organization_id,
           shortcode: "dialogflow"
         }) do
      {:ok, credential} ->
        %{
          url: credential.keys["url"],
          id: credential.secrets["project_id"],
          email: credential.secrets["project_email"]
        }

      {:error, _} ->
        %{
          url: nil,
          id: nil,
          email: nil
        }
    end
  end
end
