defmodule Glific.ThirdParty.Kaapi.Migration do
  @moduledoc """
  Onboard Glific orgs to KAAPI and store KAAPI API keys as provider credentials.
  """

  require Logger
  import Ecto.Query

  alias Glific.{
    Partners,
    Partners.Credential,
    Partners.Organization,
    Partners.Provider,
    Repo,
    ThirdParty.Kaapi.ApiClient
  }

  @doc """
  Onboard all eligible organizations from the DB.
  """
  @spec onboard_organizations_from_db() :: {:ok, any()} | {:error, String.t()}
  def onboard_organizations_from_db do
    organizations = fetch_eligible_orgs()
    {:ok, process_orgs_concurrently(organizations)}
  rescue
    e ->
      {:error, "Failed to read organizations: #{Exception.message(e)}"}
  end

  @doc """
  Onboard only the given organization IDs (but still only if they are eligible).
  """
  @spec onboard_organizations_from_db([non_neg_integer()]) ::
          {:ok, any()} | {:error, String.t()}
  def onboard_organizations_from_db(ids) when is_list(ids) do
    organizations = fetch_eligible_orgs(ids)
    {:ok, process_orgs_concurrently(organizations)}
  rescue
    e ->
      {:error, "Failed to read organizations by ids: #{Exception.message(e)}"}
  end

  @spec fetch_eligible_orgs(nil | [non_neg_integer()]) :: [map()]
  defp fetch_eligible_orgs(ids \\ nil) do
    {:ok, %Provider{id: provider_id}} =
      Repo.fetch_by(Provider, %{shortcode: "kaapi"})

    base_query =
      from(o in Organization,
        left_join: c in Credential,
        on: c.organization_id == o.id and c.provider_id == ^provider_id,
        where: is_nil(c.id),
        select: %{
          id: o.id,
          name: o.name,
          parent_org: o.parent_org,
          shortcode: o.shortcode
        },
        distinct: o.id
      )

    query =
      case ids do
        nil ->
          base_query

        list when is_list(list) ->
          from(o in subquery(base_query), where: o.id in ^list)
      end

    Repo.all(query, skip_organization_id: true)
  end

  @spec process_orgs_concurrently([map()]) :: [map()]
  defp process_orgs_concurrently(orgs) do
    orgs
    |> Task.async_stream(fn org ->
      try do
        {:ok, org.id, process_org_record(org)}
      rescue
        e -> {:error, org.id, Exception.message(e)}
      catch
        type, reason -> {:error, org.id, {type, reason}}
      end
    end)
    |> Enum.map(fn
      {:ok, {:ok, _org_id, res}} ->
        res

      {:ok, {:error, org_id, reason}} ->
        unexpected_task_error(reason, org_id)

      {:exit, reason} ->
        unexpected_task_error(reason, -1)
    end)
  end

  @spec unexpected_task_error(any(), integer()) :: map()
  defp unexpected_task_error(reason, org_id) do
    Logger.error("Task error for org_id=#{org_id}: #{inspect(reason)}")
    %{org_id: org_id, status: :error, error: "Task error: #{inspect(reason)}"}
  end

  @spec process_org_record(map()) :: any()
  defp process_org_record(%{id: _, name: _, parent_org: _, shortcode: _} = org) do
    user_name = org.shortcode
    organization_name = if org.parent_org in [nil, ""], do: org.name, else: org.parent_org

    params = %{
      organization_id: org.id,
      organization_name: organization_name,
      project_name: org.name,
      user_name: user_name
    }

    case complete_kaapi_onboarding(params) do
      {:ok, result} ->
        %{
          organization_name: organization_name,
          status: :success,
          result: result
        }

      {:error, error} ->
        Logger.error("Onboarding failed for org_id=#{org.id}: #{inspect(error)}")

        %{
          organization_name: organization_name,
          status: :error,
          error: error
        }
    end
  rescue
    e ->
      Logger.error("Onboarding crashed for org_id=#{inspect(org[:id])}: #{Exception.message(e)}")

      %{
        organization_name: org[:name],
        status: :error,
        error: Exception.message(e)
      }
  end

  @spec complete_kaapi_onboarding(map()) :: {:ok, map()} | {:error, String.t()}
  defp complete_kaapi_onboarding(params) do
    with {:ok, %{api_key: api_key}} <- ApiClient.onboard_to_kaapi(params),
         {:ok, _} <- upsert_kaapi_provider(params.organization_id, api_key) do
      {:ok, %{message: "KAAPI onboarding completed successfully"}}
    else
      {:error, error} ->
        Logger.error(
          "KAAPI onboarding failed for org: #{params.organization_id}, reason: #{inspect(error)}"
        )

        {:error, "KAAPI onboarding failed: #{inspect(error)}"}
    end
  end

  @spec upsert_kaapi_provider(non_neg_integer(), String.t()) ::
          {:ok, :created | :already_active} | {:error, any()}
  defp upsert_kaapi_provider(organization_id, api_key) do
    Partners.create_credential(%{
      organization_id: organization_id,
      shortcode: "kaapi",
      keys: %{},
      secrets: %{"api_key" => api_key},
      is_active: true
    })
    |> case do
      {:ok, _} -> {:ok, :created}
      {:error, reason} -> {:error, reason}
    end
  end
end
