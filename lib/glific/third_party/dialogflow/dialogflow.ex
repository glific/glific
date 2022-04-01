defmodule Glific.Dialogflow do
  @moduledoc """
  Module to communicate with DialogFlow v2. This module was taken directly from:
  https://github.com/resuelve/flowex/

  I pulled it into our repository since the comments were in Spanish and it did not
  seem to be maintained, that we could not use as is. The dependency list was quite old etc.
  """
  require Logger

  alias Glific.{
    Dialogflow.Intent,
    Dialogflow.Sessions,
    Flows.Action,
    Flows.FlowContext,
    Messages.Message,
    Partners,
    Repo
  }

  alias GoogleApi.Dialogflow.V2.{
    Api.Projects,
    Connection,
    Model.GoogleCloudDialogflowV2ListIntentsResponse
  }

  @doc """
  The request controller which sends and parses requests.
  """
  @spec request(non_neg_integer, atom, String.t(), String.t() | map) :: tuple
  def request(organization_id, method, path, body) do
    %{url: url, id: id, email: email} = project_info(organization_id)

    dflow_url = "#{url}/#{id}/locations/global/agent/#{path}"

    method
    |> do_request(dflow_url, body(body), headers(email, organization_id))
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, Jason.decode!(body)}

      {:ok, %Tesla.Env{status: status, body: body}} when status >= 500 ->
        {:error, Jason.decode!(body)}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error, reason}

      {:error, :timeout} ->
        {:error, "Timeout"}
    end
  end

  @spec do_request(atom(), String.t(), String.t(), list()) :: Tesla.Env.result()
  defp do_request(:post, url, body, header),
    do: Tesla.post(url, body, headers: header, opts: [adapter: [recv_timeout: 30_000]])

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
  defp headers(_email, org_id) do
    token = Partners.get_goth_token(org_id, "dialogflow")

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
    case Partners.organization(organization_id).services["dialogflow"] do
      nil ->
        %{
          url: nil,
          id: nil,
          email: nil
        }

      credential ->
        service_account = Jason.decode!(credential.secrets["service_account"])

        %{
          url: "https://dialogflow.googleapis.com/v2/projects",
          id: service_account["project_id"],
          email: service_account["client_email"]
        }
    end
  end

  @doc """
  Execute a webhook action, could be either get or post for now
  """
  @spec execute(Action.t(), FlowContext.t(), Message.t()) :: :ok
  def execute(action, context, message) do
    Sessions.detect_intent(message, context.id, action.result_name)
  end

  @doc """
  Get the list of all intents from the NLP agent
  """
  @spec get_intent_list(non_neg_integer) ::
          {:ok, GoogleCloudDialogflowV2ListIntentsResponse.t()}
          | {:ok, Tesla.Env.t()}
          | {:ok, list()}
          | {:error, any()}
  def get_intent_list(organization_id) do
    %{url: _url, id: project_id, email: _email} = project_info(organization_id)
    parent = "projects/#{project_id}/agent"

    with token <- Partners.get_goth_token(organization_id, "dialogflow"),
         false <- is_nil(token) do
      response =
        Connection.new(token.token)
        |> Projects.dialogflow_projects_agent_intents_list(parent)

      sync_with_db(response, organization_id)
      response
    end
  end

  @spec sync_with_db(tuple, non_neg_integer) :: :ok
  defp sync_with_db({:ok, res}, organization_id) do
    existing_items = Intent.get_intent_name_list(organization_id)

    intent_name_list =
      res.intents
      |> Enum.map(fn intent ->
        %{
          name: intent.displayName,
          organization_id: organization_id,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      end)
      |> List.insert_at(0, %{
        ## Default list items.
        name: "all",
        organization_id: organization_id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })
      |> Enum.filter(fn el -> !Enum.member?(existing_items, el.name) end)

    Intent
    |> Repo.insert_all(intent_name_list)

    :ok
  end

  defp sync_with_db({:error, message}, _organization_id) do
    Logger.error(message)
    :ok
  end
end
