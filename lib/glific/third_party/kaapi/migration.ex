defmodule Glific.ThirdParty.Kaapi.Migration do
  @moduledoc """
  Onboard Glific orgs to KAAPI and store KAAPI API keys as provider credentials.
  """

  use Tesla
  require Logger
  import Ecto.Query

  alias Glific.{
    Filesearch,
    Partners.Credential,
    Partners.Organization,
    Partners.Provider,
    Repo,
    TaskSupervisor,
    ThirdParty.Kaapi
  }

  plug Tesla.Middleware.FollowRedirects

  @doc """
  Onboard all eligible organizations from the DB.
  """
  @spec onboard_organizations_from_db() :: {:ok, any()} | {:error, String.t()}
  def onboard_organizations_from_db do
    organizations = fetch_eligible_orgs()
    {:ok, process_orgs_concurrently(organizations)}
  end

  @doc """
  Onboard only the given organization IDs (but still only if they are eligible).
  """
  @spec onboard_organizations_from_db([non_neg_integer()]) ::
          {:ok, any()} | {:error, String.t()}
  def onboard_organizations_from_db(ids) when is_list(ids) do
    organizations = fetch_eligible_orgs(ids)
    {:ok, process_orgs_concurrently(organizations)}
  end

  @spec fetch_eligible_orgs(nil | [non_neg_integer()]) :: [map()]
  defp fetch_eligible_orgs(ids \\ nil) do
    {:ok, %Provider{id: provider_id}} =
      Repo.fetch_by(Provider, %{shortcode: "kaapi"})

    base_query =
      from(o in Organization,
        where: o.status in [:active, :suspended, :forced_suspension],
        where: is_nil(o.deleted_at),
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
  defp process_orgs_concurrently(organizations) do
    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      organizations,
      &process_org_record/1,
      max_concurrency: 20,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} ->
        {:ok, result}

      {:exit, :timeout} ->
        Logger.error("KAAPI_ONBOARD_TIMEOUT: Organization onboard timed out after 60 seconds")
        {:error, :timeout}

      {:exit, reason} ->
        Logger.error(
          "KAAPI_ONBOARD_EXIT: Organization onboard exited with reason: #{inspect(reason)}"
        )

        {:error, reason}
    end)
  end

  @spec process_org_record(map()) :: String.t()
  defp process_org_record(%{id: id, name: org_name, parent_org: parent_org, shortcode: shortcode}) do
    open_ai_key = Application.fetch_env!(:glific, :open_ai)
    organization_name = if parent_org in [nil, ""], do: org_name, else: parent_org

    params = %{
      organization_id: id,
      organization_name: organization_name,
      project_name: shortcode,
      openai_api_key: open_ai_key
    }

    case Kaapi.onboard(params) do
      {:ok, _result} ->
        "Org #{id} onboarded successfully"

      {:error, error} ->
        "Org #{id} onboarding failed: #{inspect(error)}"
    end
  end

  @doc """
  Fetches the data from the given URL and imports all assistants for each org_id.
  """
  @spec import_asst_from_csv(String.t()) :: :ok
  def import_asst_from_csv(url) do
    {:ok, %Tesla.Env{status: 200, body: body}} = get(url)

    lines =
      body
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim_trailing(&1, "\r"))

    Task.Supervisor.async_stream_nolink(
      Glific.TaskSupervisor,
      lines,
      fn line ->
        case String.split(line, ",") do
          [org_id, assistant_id] ->
            Filesearch.import_assistant(
              String.trim(assistant_id),
              String.to_integer(String.trim(org_id))
            )

          _ ->
            {:error, :invalid_row}
        end
      end,
      max_concurrency: 20,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, {:ok, result}} ->
        Logger.info("Imported assistant: #{inspect(result)}")

      {:ok, {:error, :invalid_row}} ->
        Logger.error("Invalid CSV row")

      {:ok, {:error, reason}} ->
        Logger.error("Import failed: #{inspect(reason)}")

      {:exit, reason} ->
        Logger.error("Task crashed: #{inspect(reason)}")
    end)

    :ok
  end
end
