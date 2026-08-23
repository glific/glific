defmodule Glific.AI.Actor do
  @moduledoc """
  Establishes the identity an agent run acts under, and refuses to let it be the org root.

  Every other Oban worker in Glific calls `Repo.put_process_state/1`, which sets the current
  user to `Partners.organization(org_id).root_user`. `Repo.skip_permission?/1` then returns
  `true`, which makes `Repo.add_permission/3` a no-op — so those jobs run at full organisation
  privilege. That is fine for a BigQuery sync. It is not fine for an agent that reads whatever a
  model asks it to read on behalf of a particular staff member.

  So the agent worker never calls `put_process_state/1`. It calls `put!/2`, which sets the
  organisation and then the **requesting** user, exactly as `GlificWeb.Plugs.ContextPlug` does
  for a web request.

  ## What this actually buys

  `skip_permission?/1` returns `true` for anyone who is not both `is_restricted` and `:staff`,
  so for most users carrying the real identity narrows nothing. The point is not that it always
  restricts — it is that the agent's visibility is *exactly the requester's*, whatever that
  happens to be, instead of silently being root's. For a restricted staff user it genuinely
  narrows; for everyone else it is a no-op that stays correct when the permission model changes.

  `assert!/1` is the runtime detector: it runs on every tool call and fails loudly if the current
  user has become the org root, which is what would happen if `put_process_state/1` ever crept in
  above the loop.
  """

  alias Glific.{
    Partners,
    Repo,
    RepoReplica,
    Users.User
  }

  defmodule Error do
    @moduledoc "Raised when an agent run cannot establish, or has lost, its acting identity."
    defexception [:message]
  end

  @doc """
  Sets organisation and current-user context for an agent run, and returns the user.

  Raises `Glific.AI.Actor.Error` if the user does not belong to the organisation, which would
  otherwise be a cross-tenant read with a valid-looking job payload.
  """
  @spec put!(non_neg_integer(), non_neg_integer()) :: User.t()
  def put!(organization_id, user_id) do
    Repo.put_organization_id(organization_id)

    # organization_id is passed explicitly rather than leaning on Repo.prepare_query/3 ambient
    # scoping, per lib/glific_web/CLAUDE.md: the user_id arrives in a job payload, and a
    # mismatched one must produce a diagnosable error rather than an Ecto.NoResultsError.
    user =
      case Repo.fetch_by(User, %{id: user_id, organization_id: organization_id}) do
        {:ok, user} ->
          user

        {:error, _reason} ->
          raise Error,
            message: "no user #{user_id} in organization #{organization_id}"
      end

    # Both stores, as ContextPlug does. Setting only Repo silently reverts reads routed to the
    # replica back to root behaviour.
    # put_current_user/1 already sets Logger.metadata(user_id:), so there is nothing to add here.
    Repo.put_current_user(user)
    RepoReplica.put_current_user(user)
    ExAudit.track(user_id: user.id, organization_id: user.organization_id)

    user
  end

  @doc """
  Re-establishes an already-validated actor inside a freshly spawned process.

  Org and user context live in the process dictionary, so anything run under `Task.async/1` —
  a timeout watchdog, a parallel tool fan-out — starts with neither. `Repo.prepare_query/3` then
  raises for want of an organization id, and `assert!/2` raises for want of an acting user.

  Takes the `%User{}` the parent already fetched and validated through `put!/2` rather than
  re-reading it, so the child costs no query. Never call this without a preceding `put!/2` in the
  parent: it performs no membership check of its own.
  """
  @spec reinstate!(non_neg_integer(), User.t()) :: :ok
  def reinstate!(organization_id, %User{} = user) do
    Repo.put_organization_id(organization_id)
    Repo.put_current_user(user)
    RepoReplica.put_current_user(user)
    :ok
  end

  @doc "The user the current process is acting as. Raises if none is set."
  @spec current!() :: User.t()
  def current! do
    case Repo.get_current_user() do
      %User{} = user -> user
      _missing -> raise Error, message: "no acting user in this process"
    end
  end

  @doc """
  Asserts the process is still acting as `user_id` within `organization_id`.

  Called at the top of every tool invocation.
  """
  @spec assert!(non_neg_integer(), non_neg_integer()) :: :ok
  def assert!(organization_id, user_id) do
    user = current!()

    cond do
      Repo.get_organization_id() != organization_id ->
        raise Error, message: "organization context drifted mid-run"

      user.id == user_id ->
        :ok

      # Being the root user is not itself a failure — an organisation's root_user is its main
      # account and real admins log in as it, so refusing outright locks them out of every
      # tool-using skill. What matters is only whether the acting identity is still the one
      # that asked for this run. Root-ness is used solely to name the likely cause when it is
      # not: `Repo.put_process_state/1` swaps the current user for the org root, so a mismatch
      # that landed on root almost certainly came from that call running above the loop.
      root_user?(user, organization_id) ->
        raise Error,
          message:
            "agent is running as the organization root user instead of user #{user_id} — " <>
              "something called Repo.put_process_state/1 above the loop"

      true ->
        raise Error, message: "acting user drifted mid-run: expected #{user_id}, got #{user.id}"
    end
  end

  @doc "Runs `fun` with agent actor context established for the duration."
  @spec with_actor(non_neg_integer(), non_neg_integer(), (-> result)) :: result when result: var
  def with_actor(organization_id, user_id, fun) do
    put!(organization_id, user_id)
    fun.()
  end

  @spec root_user?(User.t(), non_neg_integer()) :: boolean()
  defp root_user?(user, organization_id) do
    case Partners.organization(organization_id) do
      %{root_user: %User{id: root_id}} -> user.id == root_id
      _no_root -> false
    end
  end
end
