defmodule Glific.KaapiKeysMigration do
  use Tesla
  plug(Tesla.Middleware.JSON, engine_opts: [keys: :atoms])

  require Logger
  import Ecto.Query

  alias Glific.Repo
  alias Glific.Partners.Organization

  @doc """
  Onboard **all** organizations from the DB.
  Returns {:ok, [%{org_id, organization_name, status, result|error}, ...]} | {:error, reason}
  """
  @spec onboard_organizations_from_db() :: {:ok, list(map())} | {:error, String.t()}
  def onboard_organizations_from_db() do
    organizations =
      from(o in Organization,
        select: %{
          id: o.id,
          name: o.name,
          parent_org: o.parent_org,
          shortcode: o.shortcode,
          email: o.email
        }
      )
      |> Repo.all(skip_organization_id: true)

    results =
      organizations
      |> Enum.map(&process_org_record/1)

    {:ok, results}
  rescue
    e ->
      {:error, "Failed to read organizations: #{Exception.message(e)}"}
  end

  @doc """
  Onboard only the organizations whose IDs are provided.
  Returns {:ok, [%{org_id, organization_name, status, result|error}, ...]} | {:error, reason}
  """
  @spec onboard_organizations_from_db([non_neg_integer()]) ::
          {:ok, list(map())} | {:error, String.t()}
  def onboard_organizations_from_db(ids) when is_list(ids) do
    organizations =
      from(o in Organization,
        where: o.id in ^ids,
        select: %{
          id: o.id,
          name: o.name,
          parent_org: o.parent_org,
          shortcode: o.shortcode,
          email: o.email
        }
      )
      |> Repo.all(skip_organization_id: true)

    results =
      organizations
      |> Enum.map(&process_org_record/1)

    {:ok, results}
  rescue
    e ->
      {:error, "Failed to read organizations by ids: #{Exception.message(e)}"}
  end

  @spec process_org_record(map()) :: map()
  defp process_org_record(%{id: _, name: _, parent_org: _, shortcode: _, email: _} = org_map) do
    do_process_org(org_map)
  end

  defp do_process_org(org) when is_map(org) do
    email = (org.email || "") |> String.trim()

    user_name =
      case String.split(email, "@", parts: 2) do
        [local, _] ->
          local = String.trim(local)
          if local == "", do: "user#{org.id}", else: local

        _ ->
          "user#{org.id}"
      end

    organization_name =
      org.parent_org
      |> to_string()
      |> String.trim()
      |> case do
        "" -> org.name
        other -> other
      end

    params = %{
      organization_id: org.id,
      org_id: org.id,
      organization_name: organization_name,
      project_name: org.name,
      email: email,
      password: generate_random_password(),
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
      Logger.error("Onboarding failed for org_id=#{inspect(org[:id])}: #{Exception.message(e)}")

      %{
        organization_name: org[:name],
        org_id: org[:id],
        status: :error,
        error: Exception.message(e)
      }
  end

  @spec complete_kaapi_onboarding(map()) :: {:ok, map()} | {:error, String.t()}
  defp complete_kaapi_onboarding(params) do
    case onboard_to_kaapi(params) do
      {:ok, %{api_key: api_key}} ->
        with {:ok, _} <-
               update_kaapi_provider(params.organization_id, api_key) do
          {:ok, %{message: "KAAPI onboarding completed successfully"}}
        else
          {:error, error} -> {:error, "KAAPI onboarding failed: #{inspect(error)}"}
        end

      {:error, error} ->
        Logger.error(
          "KAAPI onboarding failed for org: #{params.organization_id}, reason: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  @spec onboard_to_kaapi(map()) :: {:ok, map()} | {:error, String.t()}
  defp onboard_to_kaapi(params) do
    kaapi_url = Application.fetch_env!(:glific, :kaapi_endpoint)
    url = kaapi_url <> "api/v1/onboard"

    payload = %{
      organization_name: params.organization_name,
      project_name: params.project_name,
      email: params.email,
      password: params.password,
      user_name: params.user_name
    }

    key = Application.fetch_env!(:glific, :glific_x_api_key)

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
      {:ok, _credential} ->
        Logger.info("Kaapi is alredy active: for org: #{organization_id}")

      {:error, _} ->
        Glific.Partners.create_credential(%{
          organization_id: organization_id,
          shortcode: "kaapi",
          keys: %{},
          secrets: %{"api_key" => api_key},
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

  defp parse_kaapi_response({:ok, %Tesla.Env{status: status, body: body}})
       when status >= 400 do
    msg =
      case body do
        %{error: e} when is_binary(e) -> e
        _ -> "HTTP #{status}"
      end

    Logger.error("kaapi_url api error due to #{inspect(msg)}")
    {:error, msg}
  end

  defp parse_kaapi_response({:error, message}) do
    Logger.error("Kaapi api error due to #{inspect(message)}")
    {:error, "API request failed"}
  end

  @spec generate_random_password() :: String.t()
  defp generate_random_password() do
    length = 8

    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> String.slice(0, length)
  end
end
