defmodule Glific.KaapiKeysMigration do
  use Tesla
  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])
  import Logger

  @doc """
  Onboards organizations from a CSV file, processes each line and handles onboarding, credential updates, and feature flag enabling.

  ## Parameters
    * csv_path - Path to the CSV file containing the organization details.

  ## Returns
    * {:ok, list(map())} - List of organizations with their onboarding status.
    * {:error, reason} - If there is an error in processing.
  """
  @spec onboard_organizations_from_csv(String.t()) :: {:ok, list(map())} | {:error, String.t()}
  def onboard_organizations_from_csv(csv_path) do
    case File.read(csv_path) |> IO.inspect() do
      {:ok, content} ->
        results =
          content
          |> String.split("\n", trim: true)
          # Skip header row
          |> Enum.drop(1)
          |> Enum.map(&process_csv_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, results} |> IO.inspect()

      {:error, reason} ->
        {:error, "Failed to read CSV file: #{inspect(reason)}"}
    end
  end

  @spec process_csv_line(String.t()) :: map() | nil
  defp process_csv_line(line) do
    line = String.trim(line)

    fields = String.split(line, ",", trim: true)

    if length(fields) == 6 do
      [org_name, project_name, email, password, username, org_id] = fields
      password = generate_random_password() |> IO.inspect()

      params =
        %{
          organization_name: String.trim(org_name),
          project_name: String.trim(project_name),
          email: String.trim(email),
          password: password,
          user_name: String.trim(username),
          org_id: String.trim(org_id)
        }

      case complete_kaapi_onboarding(params) do
        {:ok, result} ->
          %{
            organization_name: org_name,
            org_id: org_id,
            status: :success,
            result: result
          }

        {:error, error} ->
          %{
            organization_name: org_name,
            org_id: org_id,
            status: :error,
            error: error
          }
      end
    else
      Logger.error("Invalid CSV line format: #{inspect(line)}")
      nil
    end
  end

  @spec complete_kaapi_onboarding(map()) :: {:ok, map()} | {:error, String.t()}
  defp complete_kaapi_onboarding(params) do
    with {:ok, %{api_key: api_key}} <- onboard_to_kaapi(params) |> IO.inspect(),
         {:ok, _credential} <- update_kaapi_provider(params.org_id, api_key) do
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
    org_id = Glific.Partners.Saas.organization_id()

    payload = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      email: params.email,
      password: params.password,
      user_name: params.user_name
    }

    {:ok, %{"api_key" => key}} =
      Glific.Flows.Action.fetch_kaapi_creds(org_id)

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
         })
         |> IO.inspect() do
      nil ->
        # Create new KAAPI provider credentials
        Glific.Partners.create_credential(%{
          organization_id: organization_id,
          shortcode: "kaapi",
          keys: %{},
          secrets: %{
            "api_key" => api_key
          },
          is_active: true
        })

      {:ok, credential} ->
        Glific.Partners.update_credential(
          credential,
          %{
            keys: %{},
            secrets: %{
              "api_key" => api_key
            },
            organization_id: organization_id,
            is_active: true
          }
        )
    end
  end

  @spec parse_kaapi_response(Tesla.Env.result()) :: {:ok, map()} | {:error, String.t()}
  defp parse_kaapi_response(
         {:ok,
          %Tesla.Env{status: status, body: %{api_key: api_key, organization_id: _org_id} = _body}}
       )
       when status in 200..299 do
    data = %{
      api_key: api_key
    }

    {:ok, data}
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
    random_bytes = :crypto.strong_rand_bytes(length)
    # Limit to the first `length` characters
    random_password = Base.encode64(random_bytes) |> String.slice(0, length)

    random_password
  end
end
