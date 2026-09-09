defmodule Glific.Users.Roles do
  @moduledoc """
  The legacy role hierarchy (`glific_admin > admin > manager > staff > none`) and the
  comparisons built on top of it.

  This is the single source of truth for what a role name means and how two principals
  rank against each other. `GlificWeb.Schema.Middleware.Authorize` delegates here rather
  than keeping a second copy of the hierarchy.
  """

  @rank %{glific_admin: 4, admin: 3, manager: 2, staff: 1, none: 0}

  @reserved %{
    "admin" => :admin,
    "manager" => :manager,
    "staff" => :staff,
    "no access" => :none,
    "none" => :none,
    "glific_admin" => :glific_admin,
    "glific admin" => :glific_admin
  }

  @doc """
  Numeric rank of a single role. Unknown roles rank lowest so comparisons fail closed.
  """
  @spec rank(atom() | String.t()) :: non_neg_integer()
  def rank(role) when is_atom(role) do
    # the :role_label scalar downcases input into an atom, so "Glific Admin" arrives as
    # :"glific admin" - it has to resolve through the alias map or it would rank 0
    case Map.get(@rank, role) do
      nil -> role |> Atom.to_string() |> rank()
      rank -> rank
    end
  end

  def rank(role) when is_binary(role) do
    case reserved(role) do
      nil -> 0
      atom -> Map.get(@rank, atom, 0)
    end
  end

  def rank(_role), do: 0

  @doc """
  Highest rank held across a list of roles.

  A user holding `[:staff, :glific_admin]` is a glific_admin, so every comparison must
  use the maximum rather than the first element.
  """
  @spec highest_rank(list()) :: non_neg_integer()
  def highest_rank(roles) when is_list(roles) do
    roles
    |> Enum.map(&rank/1)
    |> Enum.max(fn -> 0 end)
  end

  def highest_rank(_roles), do: 0

  @doc """
  Can the actor administer the target user?

  Peers may still manage each other, which preserves long-standing behaviour such as one
  admin editing another. Escalation is prevented by `can_grant_roles?/2`, not here - this
  check only stops reaching *up* the hierarchy.
  """
  @spec can_manage_user?(list(), list()) :: boolean()
  def can_manage_user?(actor_roles, target_roles),
    do: highest_rank(actor_roles) >= highest_rank(target_roles)

  @doc """
  Can the actor grant this set of roles? Nobody may grant a role above their own.
  """
  @spec can_grant_roles?(list(), list()) :: boolean()
  def can_grant_roles?(_actor_roles, []), do: true

  def can_grant_roles?(actor_roles, requested) when is_list(requested),
    do: highest_rank(actor_roles) >= highest_rank(requested)

  def can_grant_roles?(_actor_roles, _requested), do: false

  @doc """
  Maps a role label to its reserved legacy role, or nil for a custom role.
  """
  @spec reserved(String.t()) :: atom() | nil
  def reserved(label) when is_binary(label), do: Map.get(@reserved, String.downcase(label))

  def reserved(_label), do: nil
end
