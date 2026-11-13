defmodule Glific.LogContext do
  @moduledoc """
  Keeps `org_id` on log lines emitted outside the process that set it.

  A spawned process starts with empty logger metadata and process dictionary, so anything it logs
  (including its own crash report) loses the organization. `wrap/1` carries the caller's context
  into the spawned function, and the Oban `[:oban, :job, :start]` handler tags each job process
  with the organization found in its args.

      Task.Supervisor.start_child(Glific.TaskSupervisor, LogContext.wrap(fn -> work() end))
  """

  require Logger

  alias Glific.{Repo, RepoReplica}

  @type context :: {Keyword.t(), non_neg_integer() | nil, non_neg_integer() | nil, map() | nil}

  @doc "Wraps a 0- or 1-arity function so it runs with the calling process's org, user and logger metadata."
  @spec wrap((-> any()) | (any() -> any())) :: (-> any()) | (any() -> any())
  def wrap(fun) when is_function(fun, 0) do
    context = capture()

    fn ->
      restore(context)
      fun.()
    end
  end

  def wrap(fun) when is_function(fun, 1) do
    context = capture()

    fn arg ->
      restore(context)
      fun.(arg)
    end
  end

  @doc "Returns the organization id carried in Oban job args, or nil."
  @spec job_organization_id(map()) :: non_neg_integer() | String.t() | nil
  def job_organization_id(%{"organization_id" => org_id}) when not is_nil(org_id), do: org_id

  def job_organization_id(%{"message" => %{"organization_id" => org_id}}) when not is_nil(org_id),
    do: org_id

  def job_organization_id(%{"media" => %{"organization_id" => org_id}}) when not is_nil(org_id),
    do: org_id

  def job_organization_id(_args), do: nil

  @doc "Telemetry callback for `[:oban, :job, :start]`, run inside the job process."
  @spec handle_event(list(), map(), map(), any()) :: :ok
  def handle_event([:oban, :job, :start], _measurements, %{args: args}, _config) do
    case job_organization_id(args) do
      nil -> :ok
      org_id -> Logger.metadata(org_id: org_id)
    end
  end

  def handle_event(_event, _measurements, _meta, _config), do: :ok

  @spec capture() :: context()
  defp capture do
    {Logger.metadata(), Repo.get_organization_id(), RepoReplica.get_organization_id(),
     Repo.get_current_user()}
  end

  @spec restore(context()) :: any()
  defp restore({metadata, org_id, replica_org_id, user}) do
    Logger.metadata(metadata)
    if org_id, do: Repo.put_organization_id(org_id)
    if replica_org_id, do: RepoReplica.put_organization_id(replica_org_id)
    if user, do: Repo.put_current_user(user)
  end
end
