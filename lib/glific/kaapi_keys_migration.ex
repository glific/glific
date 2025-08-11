defmodule Glific.KaapiKeysMigration do
  use Tesla
  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  import Logger
  import Ecto.Query

  alias Glific.Repo
  alias Glific.Partners.Organization

  @doc """
  Onboard **all** organizations from the DB.
  """
  @spec onboard_organizations_from_db() :: {:ok, list(map())} | {:error, String.t()}
  def onboard_organizations_from_db() do
    try do
      organizations =
        Repo.all(from(o in Organization))

      results =
        organizations
        |> Enum.map(&process_org_record/1)
        |> Enum.reject(&is_nil/1)

      {:ok, results}
    rescue
      e ->
        {:error, "Failed to read organizations: #{Exception.message(e)}"}
    end
  end

  @doc """
  Onboard only the organizations whose IDs are provided.
  """
  @spec onboard_organizations_from_db([non_neg_integer()]) ::
          {:ok, list(map())} | {:error, String.t()}
  def onboard_organizations_from_db(ids) when is_list(ids) do
    organizations =
      Repo.all(from o in Organization, where: o.id in ^ids)

    results =
      organizations
      |> Enum.map(&process_org_record/1)
      |> Enum.reject(&is_nil/1)

    {:ok, results}
  rescue
    e ->
      # Logger.error(
      #   "Failed to read organizations by ids: #{inspect(org.id)}, message: #{Exception.message(e)}"
      # )

      {:error, "Failed to read organizations by ids: #{Exception.message(e)}"}
  end

  @spec process_org_record(Organization.t()) :: map() | nil
  defp process_org_record(%Organization{} = org) do
    email = (org.email || "") |> String.trim()
    user_name = email |> String.first() |> to_string()
    password = generate_random_password()

    organization_name =
      org.parent_org
      |> to_string()
      |> String.trim()
      |> case do
        "" -> org.name
        other -> other
      end

    params = %{
      # keep as integer
      organization_id: org.id,
      # if callers still expect org_id
      org_id: org.id,
      organization_name: organization_name,
      project_name: org.name,
      email: email,
      password: password,
      user_name: user_name
    }

    case complete_kaapi_onboarding(params) do
      {:ok, result} ->
        %{
          organization_name: organization_name,
          org_id: org.id,
          status: :success,
          result: result
        }

      {:error, error} ->
        %{
          organization_name: organization_name,
          org_id: org.id,
          status: :error,
          error: error
        }
    end
  rescue
    e ->
      Logger.error("Invalid org record (id=#{inspect(org.id)}): #{Exception.message(e)}")
      nil
  end

  @spec complete_kaapi_onboarding(map()) :: {:ok, map()} | {:error, String.t()}
  defp complete_kaapi_onboarding(params) do
    with {:ok, %{api_key: api_key}} <- onboard_to_kaapi(params),
         {:ok, _credential} <- update_kaapi_provider(params.organization_id, api_key) do
      # enable flag for THIS org id (was previously mismatched)
      FunWithFlags.enable(:is_kaapi_enabled, for: %{organization_id: params.organization_id})
      {:ok, %{message: "KAAPI onboarding completed successfully"}}
    else
      {:error, error} -> {:error, "KAAPI onboarding failed: #{inspect(error)}"}
    end
  end

  @spec onboard_to_kaapi(map()) :: {:ok, map()} | {:error, String.t()}
  defp onboard_to_kaapi(params) do
    kaapi_url = Application.fetch_env!(:glific, :kaapi_endpoint)
    url = kaapi_url <> "api/v1/onboard"

    # This is YOUR platform org used to fetch the X-API-KEY for KAAPI
    platform_org_id = Glific.Partners.Saas.organization_id()

    payload = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      email: params.email,
      password: params.password,
      user_name: params.user_name
    }

    {:ok, %{"api_key" => key}} = Glific.Flows.Action.fetch_kaapi_creds(platform_org_id)

    post(
      url,
      Jason.encode!(payload),
      headers: [
        {"X-API-KEY", key},
        {"Content-Type", "application/json"}
      ]
    )
    |> parse_kaapi_response()
  end

  @spec update_kaapi_provider(non_neg_integer(), String.t()) ::
          {:ok, map()} | {:error, any()}
  defp update_kaapi_provider(organization_id, api_key) do
    case Glific.Partners.get_credential(%{
           organization_id: organization_id,
           shortcode: "kaapi"
         }) do
      nil ->
        Glific.Partners.create_credential(%{
          organization_id: organization_id,
          shortcode: "kaapi",
          keys: %{},
          secrets: %{"api_key" => api_key},
          is_active: true
        })

      {:ok, credential} ->
        Glific.Partners.update_credential(credential, %{
          keys: %{},
          secrets: %{"api_key" => api_key},
          organization_id: organization_id,
          is_active: true
        })
    end
  end

  @spec parse_kaapi_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: %{api_key: api_key}}})
       when status in 200..299 do
    {:ok, %{api_key: api_key}}
  end

  defp parse_kaapi_response({:ok, %Tesla.Env{body: %{error: error_msg}}})
       when is_binary(error_msg) do
    Logger.error("kaapi_url api error due to #{inspect(error_msg)}")
    {:error, error_msg}
  end

  defp parse_kaapi_response({:error, message}) do
    Logger.error("Kaapi api error due to #{inspect(message)}")
    {:error, "API request failed"}
  end

  defp generate_random_password() do
    length = 8

    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> String.slice(0, length)
  end
end
